// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ISwapRouter} from "../interfaces/ISwapRouter.sol";
import {IWETH} from "../interfaces/IWETH.sol";
import {MarketConstants} from "./MarketConstants.sol";
import {CoinConstants} from "./CoinConstants.sol";
import {ICoin} from "../interfaces/ICoin.sol";
import {IProtocolRewards} from "../interfaces/IProtocolRewards.sol";
import {LpPosition} from "../types/LpPosition.sol";
import {PoolConfiguration} from "../interfaces/ICoin.sol";
import {IUniswapV3Pool} from "../interfaces/IUniswapV3Pool.sol";
import {IAirlock} from "../interfaces/IAirlock.sol";
import {UniV3Config, CoinV3Config} from "./CoinSetupV3.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {CoinLegacyMarket} from "./CoinLegacyMarket.sol";
import {CoinDopplerUniV3} from "./CoinDopplerUniV3.sol";
import {CoinConfigurationVersions} from "./CoinConfigurationVersions.sol";

struct CoinConfig {
    address protocolRewardRecipient;
    address platformReferrer;
    address currency;
    address payoutRecipient;
    address protocolRewards;
    address poolAddress;
    PoolConfiguration poolConfiguration;
    UniV3Config uniswapV3Config;
}

library UniV3BuySell {
    using SafeERC20 for IERC20;

    error AddressZero();
    error InvalidPoolVersion();

    /// @notice Executes a buy order
    /// @param recipient The recipient address of the coins
    /// @param orderSize The amount of coins to buy
    /// @param tradeReferrer The address of the trade referrer
    /// @param sqrtPriceLimitX96 The price limit for Uniswap V3 pool swap
    function buy(
        address recipient,
        uint256 orderSize,
        uint256 minAmountOut,
        uint160 sqrtPriceLimitX96,
        address tradeReferrer,
        address coin,
        CoinConfig memory coinConfig
    ) internal returns (uint256, uint256) {
        // Ensure the recipient is not the zero address
        if (recipient == address(0)) {
            revert AddressZero();
        }

        // Calculate the trade reward
        uint256 tradeReward = _calculateReward(orderSize, CoinConstants.TOTAL_FEE_BPS);

        // Calculate the remaining size
        uint256 trueOrderSize = orderSize - tradeReward;

        // Handle incoming currency
        _handleIncomingCurrency(orderSize, trueOrderSize, coinConfig.currency, coinConfig.uniswapV3Config.weth, coinConfig.uniswapV3Config.swapRouter);

        // Set up the swap parameters
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: coinConfig.currency,
            tokenOut: coin,
            fee: MarketConstants.LP_FEE,
            recipient: recipient,
            amountIn: trueOrderSize,
            amountOutMinimum: minAmountOut,
            sqrtPriceLimitX96: sqrtPriceLimitX96
        });

        // Execute the swap
        uint256 amountOut = ISwapRouter(coinConfig.uniswapV3Config.swapRouter).exactInputSingle(params);

        _handleTradeRewards(tradeReward, tradeReferrer, coinConfig);

        handleMarketRewards(coin, coinConfig);

        emit ICoin.CoinBuy(msg.sender, recipient, tradeReferrer, amountOut, coinConfig.currency, tradeReward, trueOrderSize);

        return (orderSize, amountOut);
    }

    /// @notice Executes a sell order
    /// @param recipient The recipient of the currency
    /// @param orderSize The amount of coins to sell
    /// @param minAmountOut The minimum amount of currency to receive
    /// @param sqrtPriceLimitX96 The price limit for the swap
    /// @param tradeReferrer The address of the trade referrer
    function sell(
        address recipient,
        uint256 beforeCoinBalance,
        uint256 orderSize,
        uint256 minAmountOut,
        uint160 sqrtPriceLimitX96,
        address tradeReferrer,
        CoinConfig memory coinConfig
    ) internal returns (uint256, uint256) {
        // Ensure the recipient is not the zero address
        if (recipient == address(0)) {
            revert AddressZero();
        }

        // Set the swap parameters
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(this),
            tokenOut: coinConfig.currency,
            fee: MarketConstants.LP_FEE,
            recipient: address(this),
            amountIn: orderSize,
            amountOutMinimum: minAmountOut,
            sqrtPriceLimitX96: sqrtPriceLimitX96
        });

        // Execute the swap
        uint256 amountOut = ISwapRouter(coinConfig.uniswapV3Config.swapRouter).exactInputSingle(params);

        // Record the coin balance of this contract after the swap
        uint256 afterCoinBalance = IERC20(address(this)).balanceOf(address(this));

        // If the swap was partially executed:
        if (afterCoinBalance > beforeCoinBalance) {
            // Calculate the refund
            uint256 coinRefund = afterCoinBalance - beforeCoinBalance;

            // Update the order size
            orderSize -= coinRefund;

            // Transfer the refund back to the seller
            IERC20(address(this)).safeTransfer(recipient, coinRefund);
        }

        // If currency is WETH, convert to ETH
        if (coinConfig.currency == coinConfig.uniswapV3Config.weth) {
            IWETH(coinConfig.uniswapV3Config.weth).withdraw(amountOut);
        }

        // Calculate the trade reward
        uint256 tradeReward = _calculateReward(amountOut, CoinConstants.TOTAL_FEE_BPS);

        // Calculate the payout after the fee
        uint256 payoutSize = amountOut - tradeReward;

        _handlePayout(payoutSize, recipient, coinConfig.currency, coinConfig.uniswapV3Config.weth);

        _handleTradeRewards(tradeReward, tradeReferrer, coinConfig);

        handleMarketRewards(address(this), coinConfig);

        emit ICoin.CoinSell(msg.sender, recipient, tradeReferrer, orderSize, coinConfig.currency, tradeReward, payoutSize);

        return (orderSize, payoutSize);
    }

    /// @dev Handles incoming currency transfers for buy orders; if WETH is the currency the caller has the option to send native-ETH
    /// @param orderSize The total size of the order in the currency
    /// @param trueOrderSize The actual amount being used for the swap after fees
    function _handleIncomingCurrency(uint256 orderSize, uint256 trueOrderSize, address currency, address weth, address swapRouter) internal {
        if (currency == weth && msg.value > 0) {
            if (msg.value != orderSize) {
                revert ICoin.EthAmountMismatch();
            }

            if (msg.value < CoinConstants.MIN_ORDER_SIZE) {
                revert ICoin.EthAmountTooSmall();
            }

            IWETH(weth).deposit{value: trueOrderSize}();
            IWETH(weth).approve(swapRouter, trueOrderSize);
        } else {
            // Ensure ETH is not sent with a non-ETH pair
            if (msg.value != 0) {
                revert ICoin.EthTransferInvalid();
            }

            uint256 beforeBalance = IERC20(currency).balanceOf(address(this));
            IERC20(currency).safeTransferFrom(msg.sender, address(this), orderSize);
            uint256 afterBalance = IERC20(currency).balanceOf(address(this));

            if ((afterBalance - beforeBalance) != orderSize) {
                revert ICoin.ERC20TransferAmountMismatch();
            }

            IERC20(currency).approve(swapRouter, trueOrderSize);
        }
    }

    /// @dev Handles sending ETH and ERC20 payouts and refunds to recipients
    /// @param orderPayout The amount of currency to pay out
    /// @param recipient The address to receive the payout
    function _handlePayout(uint256 orderPayout, address recipient, address currency, address weth) internal {
        if (currency == weth) {
            Address.sendValue(payable(recipient), orderPayout);
        } else {
            IERC20(currency).safeTransfer(recipient, orderPayout);
        }
    }

    /// @dev Handles calculating and depositing fees to an escrow protocol rewards contract
    function _handleTradeRewards(uint256 totalValue, address _tradeReferrer, CoinConfig memory coinConfig) internal {
        address protocolRewardRecipient = coinConfig.protocolRewardRecipient;
        address platformReferrer = coinConfig.platformReferrer;
        address currency = coinConfig.currency;
        address weth = coinConfig.uniswapV3Config.weth;
        address payoutRecipient = coinConfig.payoutRecipient;
        IProtocolRewards protocolRewards = IProtocolRewards(coinConfig.protocolRewards);

        if (_tradeReferrer == address(0)) {
            _tradeReferrer = protocolRewardRecipient;
        }

        uint256 tokenCreatorFee = _calculateReward(totalValue, CoinConstants.TOKEN_CREATOR_FEE_BPS);
        uint256 platformReferrerFee = _calculateReward(totalValue, CoinConstants.PLATFORM_REFERRER_FEE_BPS);
        uint256 tradeReferrerFee = _calculateReward(totalValue, CoinConstants.TRADE_REFERRER_FEE_BPS);
        uint256 protocolFee = totalValue - tokenCreatorFee - platformReferrerFee - tradeReferrerFee;

        if (currency == weth) {
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

        if (currency != weth) {
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

    /// @dev Collects and distributes accrued fees from all LP positions
    function handleMarketRewards(address coin, CoinConfig memory coinConfig) internal returns (ICoin.MarketRewards memory) {
        uint256 totalAmountToken0;
        uint256 totalAmountToken1;
        uint256 amount0;
        uint256 amount1;

        address poolAddress = coinConfig.poolAddress;
        address currency = coinConfig.currency;

        bool isCoinToken0 = coin < currency;
        LpPosition[] memory positions = calculatePositions(isCoinToken0, coinConfig.poolConfiguration);

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

        ICoin.MarketRewards memory rewards;

        rewards = _transferMarketRewards(token0, totalAmountToken0, rewards, coin, coinConfig);
        rewards = _transferMarketRewards(token1, totalAmountToken1, rewards, coin, coinConfig);

        emit ICoin.CoinMarketRewards(coinConfig.payoutRecipient, coinConfig.platformReferrer, coinConfig.protocolRewardRecipient, coinConfig.currency, rewards);

        return rewards;
    }

    function _transferMarketRewards(
        address token,
        uint256 totalAmount,
        ICoin.MarketRewards memory rewards,
        address coin,
        CoinConfig memory coinConfig
    ) internal returns (ICoin.MarketRewards memory) {
        address payoutRecipient = coinConfig.payoutRecipient;
        address platformReferrer = coinConfig.platformReferrer;
        address protocolRewardRecipient = coinConfig.protocolRewardRecipient;
        address currency = coinConfig.currency;
        address weth = coinConfig.uniswapV3Config.weth;
        address airlock = coinConfig.uniswapV3Config.airlock;
        address protocolRewards = coinConfig.protocolRewards;

        if (totalAmount > 0) {
            address dopplerRecipient = IAirlock(airlock).owner();
            uint256 dopplerPayout = _calculateReward(totalAmount, CoinConstants.DOPPLER_MARKET_REWARD_BPS);
            uint256 creatorPayout = _calculateReward(totalAmount, CoinConstants.CREATOR_MARKET_REWARD_BPS);
            uint256 platformReferrerPayout = _calculateReward(totalAmount, CoinConstants.PLATFORM_REFERRER_MARKET_REWARD_BPS);
            uint256 protocolPayout = totalAmount - creatorPayout - platformReferrerPayout - dopplerPayout;

            if (token == weth) {
                IWETH(weth).withdraw(totalAmount);

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
            } else if (token == coin) {
                rewards.totalAmountCoin = totalAmount;
                rewards.creatorPayoutAmountCoin = creatorPayout;
                rewards.platformReferrerAmountCoin = platformReferrerPayout;
                rewards.protocolAmountCoin = protocolPayout;

                IERC20(coin).safeTransfer(payoutRecipient, rewards.creatorPayoutAmountCoin);
                IERC20(coin).safeTransfer(platformReferrer, rewards.platformReferrerAmountCoin);
                IERC20(coin).safeTransfer(protocolRewardRecipient, rewards.protocolAmountCoin);
                IERC20(coin).safeTransfer(dopplerRecipient, dopplerPayout);
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

    /// @dev Utility for computing amounts in basis points.
    function _calculateReward(uint256 amount, uint256 bps) internal pure returns (uint256) {
        return (amount * bps) / 10_000;
    }

    function calculatePositions(bool isCoinToken0, PoolConfiguration memory poolConfiguration) internal pure returns (LpPosition[] memory positions) {
        if (poolConfiguration.version == CoinConfigurationVersions.LEGACY_POOL_VERSION) {
            positions = CoinLegacyMarket.calculatePositions(isCoinToken0, poolConfiguration);
        } else if (poolConfiguration.version == CoinConfigurationVersions.DOPPLER_UNI_V3_POOL_VERSION) {
            positions = CoinDopplerUniV3.calculatePositions(isCoinToken0, poolConfiguration);
        } else {
            revert InvalidPoolVersion();
        }
    }
}
