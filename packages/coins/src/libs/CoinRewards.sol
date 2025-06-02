// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IProtocolRewards} from "../interfaces/IProtocolRewards.sol";
import {ICoin} from "../interfaces/ICoin.sol";
import {CoinConstants} from "./CoinConstants.sol";
import {IWETH} from "../interfaces/IWETH.sol";

struct CoinConfig {
    address protocolRewardRecipient;
    address platformReferrer;
    address payoutRecipient;
    address protocolRewards;
}

library CoinRewards {
    using SafeERC20 for IERC20;

    /// @dev Handles sending ETH and ERC20 payouts and refunds to recipients
    /// @param orderPayout The amount of currency to pay out
    /// @param recipient The address to receive the payout
    function handlePayout(uint256 orderPayout, address recipient, address currency, address weth) internal {
        if (currency == weth) {
            Address.sendValue(payable(recipient), orderPayout);
        } else {
            IERC20(currency).safeTransfer(recipient, orderPayout);
        }
    }

    /// @dev Handles calculating and depositing fees to an escrow protocol rewards contract
    function handleTradeRewards(uint256 totalValue, address _tradeReferrer, CoinConfig memory coinConfig, address currency, IWETH weth) internal {
        address protocolRewardRecipient = coinConfig.protocolRewardRecipient;
        address platformReferrer = coinConfig.platformReferrer;
        address payoutRecipient = coinConfig.payoutRecipient;
        IProtocolRewards protocolRewards = IProtocolRewards(coinConfig.protocolRewards);

        if (_tradeReferrer == address(0)) {
            _tradeReferrer = protocolRewardRecipient;
        }

        uint256 tokenCreatorFee = calculateReward(totalValue, CoinConstants.TOKEN_CREATOR_FEE_BPS);
        uint256 platformReferrerFee = calculateReward(totalValue, CoinConstants.PLATFORM_REFERRER_FEE_BPS);
        uint256 tradeReferrerFee = calculateReward(totalValue, CoinConstants.TRADE_REFERRER_FEE_BPS);
        uint256 protocolFee = totalValue - tokenCreatorFee - platformReferrerFee - tradeReferrerFee;

        if (currency == address(weth)) {
            address[] memory recipients = new address[](4);
            uint256[] memory amounts = new uint256[](4);
            bytes4[] memory reasons = new bytes4[](4);

            recipients[0] = payoutRecipient;
            amounts[0] = tokenCreatorFee;
            reasons[0] = bytes4(keccak256("COIN_CREATOR_REWARD"));

            recipients[1] = platformReferrer;
            amounts[1] = platformReferrerFee;
            reasons[1] = bytes4(keccak256("COIN_PLATFORM_REFERRER_REWARD"));

            recipients[2] = _tradeReferrer;
            amounts[2] = tradeReferrerFee;
            reasons[2] = bytes4(keccak256("COIN_TRADE_REFERRER_REWARD"));

            recipients[3] = protocolRewardRecipient;
            amounts[3] = protocolFee;
            reasons[3] = bytes4(keccak256("COIN_PROTOCOL_REWARD"));

            IProtocolRewards(protocolRewards).depositBatch{value: totalValue}(recipients, amounts, reasons, "");
        }

        if (currency != address(weth)) {
            IERC20(currency).safeTransfer(payoutRecipient, tokenCreatorFee);
            IERC20(currency).safeTransfer(platformReferrer, platformReferrerFee);
            IERC20(currency).safeTransfer(_tradeReferrer, tradeReferrerFee);
            IERC20(currency).safeTransfer(protocolRewardRecipient, protocolFee);
        }

        emit ICoin.CoinTradeRewards(
            payoutRecipient,
            platformReferrer,
            _tradeReferrer,
            protocolRewardRecipient,
            tokenCreatorFee,
            platformReferrerFee,
            tradeReferrerFee,
            protocolFee,
            currency
        );
    }

    function calculateReward(uint256 amount, uint256 bps) internal pure returns (uint256) {
        return (amount * bps) / 10_000;
    }

    function transferBothRewards(
        address token0,
        uint256 totalAmountToken0,
        address token1,
        uint256 totalAmountToken1,
        address coin,
        CoinConfig memory coinConfig,
        address currency,
        IWETH weth,
        address doppler
    ) internal returns (ICoin.MarketRewards memory rewards) {
        rewards = transferMarketRewards(token0, currency, totalAmountToken0, rewards, coin, coinConfig, weth, doppler);
        rewards = transferMarketRewards(token1, currency, totalAmountToken1, rewards, coin, coinConfig, weth, doppler);
    }

    struct Distribution {
        bool isCurrency;
        uint256 totalAmount;
        uint256 creatorPayout;
        uint256 platformReferrerPayout;
        uint256 protocolPayout;
    }

    function transferMarketRewards(
        address token,
        address currency,
        uint256 totalAmount,
        ICoin.MarketRewards memory rewards,
        address coin,
        CoinConfig memory coinConfig,
        IWETH weth,
        address dopplerRecipient
    ) internal returns (ICoin.MarketRewards memory) {
        address payoutRecipient = coinConfig.payoutRecipient;
        address platformReferrer = coinConfig.platformReferrer;
        address protocolRewardRecipient = coinConfig.protocolRewardRecipient;
        address protocolRewards = coinConfig.protocolRewards;

        if (totalAmount > 0) {
            uint256 dopplerPayout = calculateReward(totalAmount, CoinConstants.DOPPLER_MARKET_REWARD_BPS);
            uint256 creatorPayout = calculateReward(totalAmount, CoinConstants.CREATOR_MARKET_REWARD_BPS);
            uint256 platformReferrerPayout = calculateReward(totalAmount, CoinConstants.PLATFORM_REFERRER_MARKET_REWARD_BPS);
            uint256 protocolPayout = totalAmount - creatorPayout - platformReferrerPayout - dopplerPayout;

            bool isCurrency = token == currency;

            if (token == address(weth)) {
                IWETH(weth).withdraw(totalAmount);

                address[] memory recipients = new address[](4);
                recipients[0] = payoutRecipient;
                recipients[1] = platformReferrer;
                recipients[2] = protocolRewardRecipient;
                recipients[3] = dopplerRecipient;

                uint256[] memory amounts = new uint256[](4);
                amounts[0] = creatorPayout;
                amounts[1] = platformReferrerPayout;
                amounts[2] = protocolPayout;
                amounts[3] = dopplerPayout;

                bytes4[] memory reasons = new bytes4[](4);
                reasons[0] = bytes4(keccak256("COIN_CREATOR_MARKET_REWARD"));
                reasons[1] = bytes4(keccak256("COIN_PLATFORM_REFERRER_MARKET_REWARD"));
                reasons[2] = bytes4(keccak256("COIN_PROTOCOL_MARKET_REWARD"));
                reasons[3] = bytes4(keccak256("COIN_DOPPLER_MARKET_REWARD"));

                IProtocolRewards(protocolRewards).depositBatch{value: totalAmount}(recipients, amounts, reasons, "");
                IProtocolRewards(protocolRewards).withdrawFor(dopplerRecipient, dopplerPayout);
            } else {
                if (!isCurrency) {
                    IERC20(coin).safeTransfer(payoutRecipient, creatorPayout);
                    IERC20(coin).safeTransfer(platformReferrer, platformReferrerPayout);
                    IERC20(coin).safeTransfer(protocolRewardRecipient, protocolPayout);
                    IERC20(coin).safeTransfer(dopplerRecipient, dopplerPayout);
                } else {
                    IERC20(currency).safeTransfer(payoutRecipient, creatorPayout);
                    IERC20(currency).safeTransfer(platformReferrer, platformReferrerPayout);
                    IERC20(currency).safeTransfer(protocolRewardRecipient, protocolPayout);
                    IERC20(currency).safeTransfer(dopplerRecipient, dopplerPayout);
                }
            }

            if (isCurrency) {
                rewards.totalAmountCurrency = totalAmount;
                rewards.creatorPayoutAmountCurrency = creatorPayout;
                rewards.platformReferrerAmountCurrency = platformReferrerPayout;
                rewards.protocolAmountCurrency = protocolPayout;
            } else {
                rewards.totalAmountCoin = totalAmount;
                rewards.creatorPayoutAmountCoin = creatorPayout;
                rewards.platformReferrerAmountCoin = platformReferrerPayout;
                rewards.protocolAmountCoin = protocolPayout;
            }
        }

        return rewards;
    }
}
