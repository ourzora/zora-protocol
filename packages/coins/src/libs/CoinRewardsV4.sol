// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {CoinV4} from "../CoinV4.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {LpPosition} from "../types/LpPosition.sol";
import {V4Liquidity} from "./V4Liquidity.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHasRewardsRecipients} from "../interfaces/ICoin.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ICoin} from "../interfaces/ICoin.sol";
import {IZoraV4CoinHook} from "../interfaces/IZoraV4CoinHook.sol";

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

    function collectAndDistributeMarketRewards(
        IPoolManager poolManager,
        PoolKey memory key,
        LpPosition[] storage positions,
        bytes calldata hookData,
        IHasRewardsRecipients coin
    ) internal {
        // Collect lp fees to get balances
        (int128 fees0, int128 fees1) = V4Liquidity.collectAndTakeFees(poolManager, key, positions);

        // distribute the fees as market rewards
        CoinRewardsV4.distributeMarketRewards(key.currency0, key.currency1, uint128(fees0), uint128(fees1), coin, getTradeReferral(hookData));
    }

    function getTradeReferral(bytes calldata hookData) internal view returns (address) {
        return hookData.length > 0 ? abi.decode(hookData, (address)) : address(0);
    }

    function distributeMarketRewards(
        Currency currencyA,
        Currency currencyB,
        uint128 fee0,
        uint128 fee1,
        IHasRewardsRecipients coin,
        address tradeReferrer
    ) internal {
        // todo: fill this out
        address payoutRecipient = coin.payoutRecipient();
        address platformReferrer = coin.platformReferrer();
        address protocolRewardRecipient = coin.protocolRewardRecipient();
        address doppler = coin.doppler();

        MarketRewards memory rewardsA = _distributeCurrencyRewards(
            currencyA,
            fee0,
            payoutRecipient,
            platformReferrer,
            protocolRewardRecipient,
            doppler,
            tradeReferrer
        );

        MarketRewards memory rewardsB = _distributeCurrencyRewards(
            currencyB,
            fee1,
            payoutRecipient,
            platformReferrer,
            protocolRewardRecipient,
            doppler,
            tradeReferrer
        );

        bool currencyAIsCoin = Currency.unwrap(currencyA) == address(coin);
        MarketRewards memory rewardsCoin = currencyAIsCoin ? rewardsA : rewardsB;
        MarketRewards memory rewardsCurrency = currencyAIsCoin ? rewardsB : rewardsA;

        IZoraV4CoinHook.MarketRewardsV4 memory rewards = IZoraV4CoinHook.MarketRewardsV4({
            creatorPayoutAmountCurrency: rewardsCurrency.creatorAmount,
            creatorPayoutAmountCoin: rewardsCoin.creatorAmount,
            platformReferrerAmountCurrency: rewardsCurrency.platformReferrerAmount,
            platformReferrerAmountCoin: rewardsCoin.platformReferrerAmount,
            tradeReferrerAmountCurrency: rewardsCurrency.tradeReferrerAmount,
            tradeReferrerAmountCoin: rewardsCoin.tradeReferrerAmount,
            protocolAmountCurrency: rewardsCurrency.protocolAmount,
            protocolAmountCoin: rewardsCoin.protocolAmount,
            dopplerAmountCurrency: rewardsCurrency.dopplerAmount,
            dopplerAmountCoin: rewardsCoin.dopplerAmount
        });

        emit IZoraV4CoinHook.CoinMarketRewardsV4(
            address(coin),
            Currency.unwrap(currencyAIsCoin ? currencyB : currencyA),
            payoutRecipient,
            platformReferrer,
            tradeReferrer,
            protocolRewardRecipient,
            doppler,
            rewards
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
