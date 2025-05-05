// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {CoinConstants} from "./CoinConstants.sol";
import {LpPosition} from "../types/LpPosition.sol";
import {IUniswapV3Pool} from "../interfaces/IUniswapV3Pool.sol";
import {ISwapRouter} from "../interfaces/ISwapRouter.sol";
import {CoinMarket} from "./CoinMarket.sol";
import {IWETH} from "../interfaces/IWETH.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

library UniV3Rewards {
    using SafeERC20 for IERC20;

    /// @notice The rewards accrued from the market's liquidity position
    struct MarketRewards {
        uint256 totalAmountCurrency;
        uint256 totalAmountCoin;
        uint256 creatorPayoutAmountCurrency;
        uint256 creatorPayoutAmountCoin;
        uint256 platformReferrerAmountCurrency;
        uint256 platformReferrerAmountCoin;
        uint256 protocolAmountCurrency;
        uint256 protocolAmountCoin;
    }

    /// @notice Emitted when trade rewards are distributed
    /// @param payoutRecipient The address of the creator rewards payout recipient
    /// @param platformReferrer The address of the platform referrer
    /// @param tradeReferrer The address of the trade referrer
    /// @param protocolRewardRecipient The address of the protocol reward recipient
    /// @param creatorReward The reward for the creator
    /// @param platformReferrerReward The reward for the platform referrer
    /// @param traderReferrerReward The reward for the trade referrer
    /// @param protocolReward The reward for the protocol
    /// @param currency The address of the currency
    event CoinTradeRewards(
        address indexed payoutRecipient,
        address indexed platformReferrer,
        address indexed tradeReferrer,
        address protocolRewardRecipient,
        uint256 creatorReward,
        uint256 platformReferrerReward,
        uint256 traderReferrerReward,
        uint256 protocolReward,
        address currency
    );

    /// @dev Utility for computing amounts in basis points.
    function _calculateReward(uint256 amount, uint256 bps) internal pure returns (uint256) {
        return (amount * bps) / 10_000;
    }

    /// @dev Handles calculating and depositing fees to an escrow protocol rewards contract
    function _handleTradeRewards(
        uint256 totalValue,
        address _tradeReferrer,
        address _payoutRecipient,
        address _platformReferrer,
        address _protocolRewardRecipient,
        address _currency
    ) internal {
        if (_tradeReferrer == address(0)) {
            _tradeReferrer = _protocolRewardRecipient;
        }

        uint256 tokenCreatorFee = _calculateReward(totalValue, CoinConstants.TOKEN_CREATOR_FEE_BPS);
        uint256 platformReferrerFee = _calculateReward(totalValue, CoinConstants.PLATFORM_REFERRER_FEE_BPS);
        uint256 tradeReferrerFee = _calculateReward(totalValue, CoinConstants.TRADE_REFERRER_FEE_BPS);
        uint256 protocolFee = totalValue - tokenCreatorFee - platformReferrerFee - tradeReferrerFee;

        if (_currency == WETH) {
            address[] memory recipients = new address[](4);
            uint256[] memory amounts = new uint256[](4);
            bytes4[] memory reasons = new bytes4[](4);

            recipients[0] = _payoutRecipient;
            amounts[0] = tokenCreatorFee;
            reasons[0] = bytes4(keccak256("COIN_CREATOR_REWARD"));

            recipients[1] = _platformReferrer;
            amounts[1] = platformReferrerFee;
            reasons[1] = bytes4(keccak256("COIN_PLATFORM_REFERRER_REWARD"));

            recipients[2] = _tradeReferrer;
            amounts[2] = tradeReferrerFee;
            reasons[2] = bytes4(keccak256("COIN_TRADE_REFERRER_REWARD"));

            recipients[3] = _protocolRewardRecipient;
            amounts[3] = protocolFee;
            reasons[3] = bytes4(keccak256("COIN_PROTOCOL_REWARD"));

            IProtocolRewards(protocolRewards).depositBatch{value: totalValue}(recipients, amounts, reasons, "");
        }

        if (currency != WETH) {
            IERC20(currency).safeTransfer(_payoutRecipient, tokenCreatorFee);
            IERC20(currency).safeTransfer(_platformReferrer, platformReferrerFee);
            IERC20(currency).safeTransfer(_tradeReferrer, tradeReferrerFee);
            IERC20(currency).safeTransfer(_protocolRewardRecipient, protocolFee);
        }

        emit CoinTradeRewards(
            _payoutRecipient,
            _platformReferrer,
            _tradeReferrer,
            _protocolRewardRecipient,
            tokenCreatorFee,
            platformReferrerFee,
            tradeReferrerFee,
            protocolFee,
            currency
        );
    }

    /// @dev Collects and distributes accrued fees from all LP positions
    function _handleMarketRewards(
        address poolAddress,
        address currency,
        address payoutRecipient,
        address platformReferrer,
        address protocolRewardRecipient,
        address airlock
    ) internal returns (MarketRewards memory) {
        uint256 totalAmountToken0;
        uint256 totalAmountToken1;
        uint256 amount0;
        uint256 amount1;

        bool isCoinToken0 = address(this) < currency;
        LpPosition[] memory positions = CoinMarket.calculatePositions(isCoinToken0, poolConfiguration);

        for (uint256 i; i < positions.length; i++) {
            // Must burn to update the collect mapping on the pool
            IUniswapV3Pool(poolAddress).burn(positions[i].tickLower, positions[i].tickUpper, 0);

            (amount0, amount1) = IUniswapV3Pool(poolAddress).collect(
                address(this),
                positions[i].tickLower,
                positions[i].tickUpper,
                type(uint128).max,
                type(uint128).max
            );

            totalAmountToken0 += amount0;
            totalAmountToken1 += amount1;
        }

        address token0 = currency < address(this) ? currency : address(this);
        address token1 = currency < address(this) ? address(this) : currency;

        MarketRewards memory rewards;

        rewards = _transferMarketRewards(token0, totalAmountToken0, rewards);
        rewards = _transferMarketRewards(token1, totalAmountToken1, rewards);

        emit CoinMarketRewards(payoutRecipient, platformReferrer, protocolRewardRecipient, currency, rewards);

        return rewards;
    }

    function _transferMarketRewards(address token, uint256 totalAmount, MarketRewards memory rewards) internal returns (MarketRewards memory) {
        if (totalAmount > 0) {
            address dopplerRecipient = IAirlock(airlock).owner();
            uint256 dopplerPayout = _calculateReward(totalAmount, CoinConstants.DOPPLER_MARKET_REWARD_BPS);
            uint256 creatorPayout = _calculateReward(totalAmount, CoinConstants.CREATOR_MARKET_REWARD_BPS);
            uint256 platformReferrerPayout = _calculateReward(totalAmount, CoinConstants.PLATFORM_REFERRER_MARKET_REWARD_BPS);
            uint256 protocolPayout = totalAmount - creatorPayout - platformReferrerPayout - dopplerPayout;

            if (token == WETH) {
                IWETH(WETH).withdraw(totalAmount);

                rewards.totalAmountCurrency = totalAmount;
                rewards.creatorPayoutAmountCurrency = creatorPayout;
                rewards.platformReferrerAmountCurrency = platformReferrerPayout;
                rewards.protocolAmountCurrency = protocolPayout;

                address[] memory recipients = new address[](4);
                recipients[0] = payoutRecipient;
                recipients[1] = platformReferrer;
                recipients[2] = protocolRewardRecipient;
                recipients[3] = dopplerRecipient;

                uint256[] memory amounts = new uint256[](4);
                amounts[0] = rewards.creatorPayoutAmountCurrency;
                amounts[1] = rewards.platformReferrerAmountCurrency;
                amounts[2] = rewards.protocolAmountCurrency;
                amounts[3] = dopplerPayout;

                bytes4[] memory reasons = new bytes4[](4);
                reasons[0] = bytes4(keccak256("COIN_CREATOR_MARKET_REWARD"));
                reasons[1] = bytes4(keccak256("COIN_PLATFORM_REFERRER_MARKET_REWARD"));
                reasons[2] = bytes4(keccak256("COIN_PROTOCOL_MARKET_REWARD"));
                reasons[3] = bytes4(keccak256("COIN_DOPPLER_MARKET_REWARD"));

                IProtocolRewards(protocolRewards).depositBatch{value: totalAmount}(recipients, amounts, reasons, "");
                IProtocolRewards(protocolRewards).withdrawFor(dopplerRecipient, dopplerPayout);
            } else if (token == address(this)) {
                rewards.totalAmountCoin = totalAmount;
                rewards.creatorPayoutAmountCoin = creatorPayout;
                rewards.platformReferrerAmountCoin = platformReferrerPayout;
                rewards.protocolAmountCoin = protocolPayout;

                _transfer(address(this), payoutRecipient, rewards.creatorPayoutAmountCoin);
                _transfer(address(this), platformReferrer, rewards.platformReferrerAmountCoin);
                _transfer(address(this), protocolRewardRecipient, rewards.protocolAmountCoin);
                _transfer(address(this), dopplerRecipient, dopplerPayout);
            } else {
                rewards.totalAmountCurrency = totalAmount;
                rewards.creatorPayoutAmountCurrency = creatorPayout;
                rewards.platformReferrerAmountCurrency = platformReferrerPayout;
                rewards.protocolAmountCurrency = protocolPayout;

                IERC20(currency).safeTransfer(payoutRecipient, creatorPayout);
                IERC20(currency).safeTransfer(platformReferrer, platformReferrerPayout);
                IERC20(currency).safeTransfer(protocolRewardRecipient, protocolPayout);
                IERC20(currency).safeTransfer(dopplerRecipient, dopplerPayout);
            }
        }

        return rewards;
    }
}
