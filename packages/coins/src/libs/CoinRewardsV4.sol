// SPDX-License-Identifier: ZORA-DELAYED-OSL-v1
// This software is licensed under the Zora Delayed Open Source License.
// Under this license, you may use, copy, modify, and distribute this software for
// non-commercial purposes only. Commercial use and competitive products are prohibited
// until the "Open Date" (3 years from first public distribution or earlier at Zora's discretion),
// at which point this software automatically becomes available under the MIT License.
// Full license terms available at: https://docs.zora.co/coins/license
pragma solidity ^0.8.28;

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PathKey} from "@uniswap/v4-periphery/src/libraries/PathKey.sol";
import {ModifyLiquidityParams} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {SafeCast} from "@uniswap/v4-core/src/libraries/SafeCast.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {TransientStateLibrary} from "@uniswap/v4-core/src/libraries/TransientStateLibrary.sol";
import {LpPosition} from "../types/LpPosition.sol";
import {V4Liquidity} from "./V4Liquidity.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {DopplerMath} from "../libs/DopplerMath.sol";
import {LiquidityAmounts} from "../utils/uniswap/LiquidityAmounts.sol";
import {IHasRewardsRecipients} from "../interfaces/IHasRewardsRecipients.sol";
import {ICoin} from "../interfaces/ICoin.sol";
import {IZoraV4CoinHook} from "../interfaces/IZoraV4CoinHook.sol";
import {IHasSwapPath} from "../interfaces/ICoin.sol";
import {V4Liquidity} from "./V4Liquidity.sol";
import {UniV4SwapToCurrency} from "./UniV4SwapToCurrency.sol";
import {ICreatorCoinHook} from "../interfaces/ICreatorCoinHook.sol";
import {IHasCoinType} from "../interfaces/ICoin.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {ICreatorCoin} from "../interfaces/ICreatorCoin.sol";

library CoinRewardsV4 {
    using SafeERC20 for IERC20;

    // Creator gets 62.5% of market rewards (0.50% of total 1% fee)
    // Market rewards = 80% of total fee (0.80% of 1%)
    uint256 public constant CREATOR_REWARD_BPS = 6250;

    // Platform referrer gets 25% of market rewards (0.20% of total 1% fee)
    uint256 public constant CREATE_REFERRAL_REWARD_BPS = 2500;

    // Trade referrer gets 5% of market rewards (0.04% of total 1% fee)
    uint256 public constant TRADE_REFERRAL_REWARD_BPS = 500;

    // Doppler gets 1.25% of market rewards (0.01% of total 1% fee)
    uint256 public constant DOPPLER_REWARD_BPS = 125;

    // LPs get 20% of total fee (0.20% of 1%)
    uint256 public constant LP_REWARD_BPS = 2000;

    function getTradeReferral(bytes calldata hookData) internal pure returns (address) {
        return hookData.length >= 20 ? abi.decode(hookData, (address)) : address(0);
    }

    /// @dev Converts collected fees from LP positions into target payout currency, and transfers to hook contract, so
    ///      that they can later be distributed as rewards.
    /// @param poolManager The pool manager instance
    /// @param fees0 The amount of fees collected in currency0
    /// @param fees1 The amount of fees collected in currency1
    /// @param payoutSwapPath The swap path to convert fees to target currency
    /// @return receivedCurrency The final currency after swapping
    /// @return receivedAmount The final amount after swapping
    function convertToPayoutCurrency(
        IPoolManager poolManager,
        uint128 fees0,
        uint128 fees1,
        IHasSwapPath.PayoutSwapPath memory payoutSwapPath
    ) internal returns (Currency receivedCurrency, uint128 receivedAmount) {
        // This handles multi-hop swaps if needed (e.g. coin -> backingCoin -> backingCoin's currency)
        (receivedCurrency, receivedAmount) = UniV4SwapToCurrency.swapToPath(poolManager, fees0, fees1, payoutSwapPath.currencyIn, payoutSwapPath.path);

        // Transfer the final converted currency amount to this contract for distribution
        // This makes the tokens available for the subsequent reward distribution
        if (receivedAmount > 0) {
            poolManager.take(receivedCurrency, address(this), receivedAmount);
        }
    }

    /// @dev Computes the LP reward and remaining amount for market rewards from the total amount
    function computeLpReward(uint128 totalBackingAmount) internal pure returns (uint128 lpRewardAmount) {
        lpRewardAmount = uint128(calculateReward(uint256(totalBackingAmount), LP_REWARD_BPS));
    }

    function convertDeltaToPositiveUint128(int256 delta) internal pure returns (uint128) {
        if (delta < 0) {
            revert SafeCast.SafeCastOverflow();
        }
        return uint128(uint256(delta));
    }

    function getCurrencyZeroBalance(IPoolManager poolManager, PoolKey calldata key) internal view returns (uint128) {
        return convertDeltaToPositiveUint128(TransientStateLibrary.currencyDelta(poolManager, address(this), key.currency0));
    }

    function getCurrencyOneBalance(IPoolManager poolManager, PoolKey calldata key) internal view returns (uint128) {
        return convertDeltaToPositiveUint128(TransientStateLibrary.currencyDelta(poolManager, address(this), key.currency1));
    }

    /// @notice Mints LP rewards by creating new liquidity positions from collected fees
    /// @dev Splits collected fees between LP rewards and market rewards, then mints new LP positions
    ///      with the LP reward portion. The remaining amount becomes market rewards for distribution.
    /// @param poolManager The pool manager instance
    /// @param key The pool key identifying the specific pool
    /// @param fees0 The amount of fees collected in currency0
    /// @param fees1 The amount of fees collected in currency1
    /// @return marketRewardsAmount0 The amount of currency0 remaining for market rewards
    /// @return marketRewardsAmount1 The amount of currency1 remaining for market rewards
    function mintLpReward(
        IPoolManager poolManager,
        PoolKey calldata key,
        int128 fees0,
        int128 fees1
    ) internal returns (uint128 marketRewardsAmount0, uint128 marketRewardsAmount1) {
        if (fees0 > 0) {
            uint128 lpRewardAmount0 = computeLpReward(uint128(fees0));
            if (lpRewardAmount0 > 0) {
                _modifyLiquidity(poolManager, key, lpRewardAmount0, true);
            }
        }

        if (fees1 > 0) {
            uint128 lpRewardAmount1 = computeLpReward(uint128(fees1));
            if (lpRewardAmount1 > 0) {
                _modifyLiquidity(poolManager, key, lpRewardAmount1, false);
            }
        }

        marketRewardsAmount0 = getCurrencyZeroBalance(poolManager, key);
        marketRewardsAmount1 = getCurrencyOneBalance(poolManager, key);
    }

    /// @notice Mints a single-sided LP position
    /// @dev The position is created for a single tick spacing range, either entirely above or below the current tick, to ensure only one currency is required
    function _modifyLiquidity(IPoolManager poolManager, PoolKey calldata key, uint128 lpRewardAmount, bool isFeesToken0) private {
        // Get the current tick to determine where to place the new position.
        (, int24 currentTick, , ) = StateLibrary.getSlot0(poolManager, key.toId());

        int24 tickLower;
        int24 tickUpper;

        if (isFeesToken0) {
            // For token0 fees, the position must be entirely above the current tick
            // We set the lower tick to be at least two tick spacings away to ensure it's not in the active range
            int24 minTickLower = currentTick + (key.tickSpacing * 2);
            tickLower = DopplerMath.alignTickToTickSpacing(true, minTickLower, key.tickSpacing);
            tickUpper = tickLower + key.tickSpacing;
        } else {
            // For token1 fees, the position must be entirely below the current tick
            // We set the upper tick to be at least two tick spacings away
            int24 maxTickUpper = currentTick - (key.tickSpacing * 2);
            tickUpper = DopplerMath.alignTickToTickSpacing(false, maxTickUpper, key.tickSpacing);
            tickLower = tickUpper - key.tickSpacing;
        }

        uint160 sqrtPriceA = TickMath.getSqrtPriceAtTick(tickLower);
        uint160 sqrtPriceB = TickMath.getSqrtPriceAtTick(tickUpper);

        uint128 liquidity = isFeesToken0
            ? LiquidityAmounts.getLiquidityForAmount0(sqrtPriceA, sqrtPriceB, lpRewardAmount)
            : LiquidityAmounts.getLiquidityForAmount1(sqrtPriceA, sqrtPriceB, lpRewardAmount);

        if (liquidity > 0) {
            ModifyLiquidityParams memory params = ModifyLiquidityParams({
                tickLower: tickLower,
                tickUpper: tickUpper,
                liquidityDelta: SafeCast.toInt256(liquidity),
                salt: 0
            });
            poolManager.modifyLiquidity(key, params, "");
        }
    }

    /// @notice Distributes collected market fees as rewards to various recipients including creator, referrers, protocol, and doppler
    /// @dev Calculates reward amounts based on predefined basis points and transfers the specified currency to each recipient
    /// @param currency The currency token to distribute as rewards (can be native ETH if address is zero)
    /// @param fees The total amount of fees collected to be distributed
    /// @param coin The coin contract instance that implements IHasRewardsRecipients to get recipient addresses
    /// @param tradeReferrer The address of the trade referrer who should receive trade referral rewards (can be zero address)
    function distributeMarketRewards(
        Currency currency,
        uint128 fees,
        IHasRewardsRecipients coin,
        address tradeReferrer,
        IHasCoinType.CoinType coinType
    ) internal {
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

        if (coinType == IHasCoinType.CoinType.Creator) {
            emit ICreatorCoinHook.CreatorCoinRewards(
                address(coin),
                Currency.unwrap(currency),
                payoutRecipient,
                protocolRewardRecipient,
                rewards.creatorAmount,
                rewards.protocolAmount
            );
        }
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

    function getCoinType(IHasRewardsRecipients coin) internal view returns (IHasCoinType.CoinType) {
        // first check if the coin supports the IHasCoinType interface - if it does, we can use that
        if (IERC165(address(coin)).supportsInterface(type(IHasCoinType).interfaceId)) {
            return IHasCoinType(address(coin)).coinType();
        }

        // see if its a legacy creator coin
        return isLegacyCreatorCoin(coin) ? IHasCoinType.CoinType.Creator : IHasCoinType.CoinType.Content;
    }

    function isLegacyCreatorCoin(IHasRewardsRecipients coin) internal view returns (bool) {
        // try to call the method `getClaimableAmount` on the legacy creator coin, if it succeeds, then it is a legacy creator coin,
        // otherwise we can assume it is a content coin
        try ICreatorCoin(address(coin)).getClaimableAmount() returns (uint256) {
            return true;
        } catch {
            return false;
        }
    }
}
