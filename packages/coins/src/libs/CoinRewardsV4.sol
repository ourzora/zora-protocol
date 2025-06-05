// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {LpPosition} from "../types/LpPosition.sol";
import {V4Liquidity} from "./V4Liquidity.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHasRewardsRecipients} from "../interfaces/ICoin.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ICoin} from "../interfaces/ICoin.sol";
import {IZoraV4CoinHook} from "../interfaces/IZoraV4CoinHook.sol";
import {UniV4SwapToCurrency} from "./UniV4SwapToCurrency.sol";
import {IHasSwapPath} from "../interfaces/ICoinV4.sol";

library CoinRewardsV4 {
    using SafeERC20 for IERC20;

    // creator gets 50% of the total fee
    uint256 public constant CREATOR_REWARD_BPS = 5000;

    // create referrer gets 15% of the total fee
    uint256 public constant CREATE_REFERRAL_REWARD_BPS = 1500;

    // trade referrer gets 10% of the total fee
    uint256 public constant TRADE_REFERRAL_REWARD_BPS = 1500;

    // doppler gets 5% of the total fee
    uint256 public constant DOPPLER_REWARD_BPS = 500;

    function getTradeReferral(bytes calldata hookData) internal pure returns (address) {
        return hookData.length > 0 ? abi.decode(hookData, (address)) : address(0);
    }

    /// @notice Collects fees from LP positions, swaps them to target payout currency, and transfers to hook contract, so
    /// that they can later be distributed as rewards.
    /// @param poolManager The pool manager instance
    /// @param key The pool key
    /// @param positions The LP positions to collect fees from
    /// @param payoutSwapPath The swap path to convert fees to target currency
    /// @return fees0 The amount of fees collected in currency0
    /// @return fees1 The amount of fees collected in currency1
    /// @return receivedCurrency The final currency after swapping
    /// @return receivedAmount The final amount after swapping
    function collectFeesAndConvertToPayout(
        IPoolManager poolManager,
        PoolKey memory key,
        LpPosition[] storage positions,
        IHasSwapPath.PayoutSwapPath memory payoutSwapPath
    ) internal returns (int128 fees0, int128 fees1, Currency receivedCurrency, uint128 receivedAmount) {
        // Step 1: Collect accrued fees from all LP positions in both token0 and token1
        (fees0, fees1) = V4Liquidity.collectFees(poolManager, key, positions);

        // This handles multi-hop swaps if needed (e.g. coin -> backingCoin -> backingCoin's currency)
        (receivedCurrency, receivedAmount) = UniV4SwapToCurrency.swapToPath(
            poolManager,
            uint128(fees0),
            uint128(fees1),
            payoutSwapPath.currencyIn,
            payoutSwapPath.path
        );

        // Step 3: Transfer the final converted currency amount to this contract for distribution
        // This makes the tokens available for the subsequent reward distribution
        if (receivedAmount > 0) {
            poolManager.take(receivedCurrency, address(this), receivedAmount);
        }
    }

    /// @notice Distributes collected market fees as rewards to various recipients including creator, referrers, protocol, and doppler
    /// @dev Calculates reward amounts based on predefined basis points and transfers the specified currency to each recipient
    /// @param currency The currency token to distribute as rewards (can be native ETH if address is zero)
    /// @param fees The total amount of fees collected to be distributed
    /// @param coin The coin contract instance that implements IHasRewardsRecipients to get recipient addresses
    /// @param tradeReferrer The address of the trade referrer who should receive trade referral rewards (can be zero address)
    function distributeMarketRewards(Currency currency, uint128 fees, IHasRewardsRecipients coin, address tradeReferrer) internal {
        address payoutRecipient = coin.payoutRecipient();
        address platformReferrer = coin.platformReferrer();
        address protocolRewardRecipient = coin.protocolRewardRecipient();
        address doppler = coin.dopplerFeeRecipient();

        MarketRewards memory rewards = _distributeCurrencyRewards(
            currency,
            fees,
            payoutRecipient,
            platformReferrer,
            protocolRewardRecipient,
            doppler,
            tradeReferrer
        );

        IZoraV4CoinHook.MarketRewardsV4 memory marketRewards = IZoraV4CoinHook.MarketRewardsV4({
            creatorPayoutAmountCurrency: rewards.creatorAmount,
            creatorPayoutAmountCoin: 0,
            platformReferrerAmountCurrency: rewards.platformReferrerAmount,
            platformReferrerAmountCoin: 0,
            tradeReferrerAmountCurrency: rewards.tradeReferrerAmount,
            tradeReferrerAmountCoin: 0,
            protocolAmountCurrency: rewards.protocolAmount,
            protocolAmountCoin: 0,
            dopplerAmountCurrency: rewards.dopplerAmount,
            dopplerAmountCoin: 0
        });

        emit IZoraV4CoinHook.CoinMarketRewardsV4(
            address(coin),
            Currency.unwrap(currency),
            payoutRecipient,
            platformReferrer,
            tradeReferrer,
            protocolRewardRecipient,
            doppler,
            marketRewards
        );
    }

    struct MarketRewards {
        uint256 platformReferrerAmount;
        uint256 tradeReferrerAmount;
        uint256 protocolAmount;
        uint256 creatorAmount;
        uint256 dopplerAmount;
    }

    function _distributeCurrencyRewards(
        Currency currency,
        uint128 fee,
        address payoutRecipient,
        address platformReferrer,
        address protocolRewardRecipient,
        address doppler,
        address tradeReferral
    ) internal returns (MarketRewards memory rewards) {
        rewards = _computeMarketRewards(fee, tradeReferral != address(0), platformReferrer != address(0));

        if (platformReferrer != address(0)) {
            _transferCurrency(currency, rewards.platformReferrerAmount, platformReferrer);
        }
        if (tradeReferral != address(0)) {
            _transferCurrency(currency, rewards.tradeReferrerAmount, tradeReferral);
        }
        _transferCurrency(currency, rewards.creatorAmount, payoutRecipient);
        _transferCurrency(currency, rewards.dopplerAmount, doppler);
        _transferCurrency(currency, rewards.protocolAmount, protocolRewardRecipient);
    }

    function _transferCurrency(Currency currency, uint256 amount, address to) internal {
        if (amount == 0) {
            return;
        }

        if (currency.isAddressZero()) {
            (bool success, ) = payable(to).call{value: amount}("");
            if (!success) {
                revert ICoin.EthTransferFailed();
            }
        } else {
            IERC20(Currency.unwrap(currency)).safeTransfer(to, amount);
        }
    }

    function _computeMarketRewards(uint128 fee, bool hasTradeReferral, bool hasCreateReferral) internal pure returns (MarketRewards memory rewards) {
        if (fee == 0) {
            return rewards;
        }

        uint256 totalAmount = uint256(fee);
        rewards.platformReferrerAmount = hasCreateReferral ? calculateReward(totalAmount, CREATE_REFERRAL_REWARD_BPS) : 0;
        rewards.tradeReferrerAmount = hasTradeReferral ? calculateReward(totalAmount, TRADE_REFERRAL_REWARD_BPS) : 0;
        rewards.creatorAmount = calculateReward(totalAmount, CREATOR_REWARD_BPS);
        rewards.dopplerAmount = calculateReward(totalAmount, DOPPLER_REWARD_BPS);
        rewards.protocolAmount = totalAmount - rewards.platformReferrerAmount - rewards.tradeReferrerAmount - rewards.creatorAmount - rewards.dopplerAmount;
    }

    function calculateReward(uint256 amount, uint256 bps) internal pure returns (uint256) {
        return (amount * bps) / 10_000;
    }
}
