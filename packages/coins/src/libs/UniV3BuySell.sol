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
import {CoinV3Config} from "./CoinSetupV3.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {CoinDopplerUniV3} from "./CoinDopplerUniV3.sol";
import {CoinConfigurationVersions} from "./CoinConfigurationVersions.sol";
import {CoinRewards, CoinConfig} from "./CoinRewards.sol";
struct SellResult {
    uint256 payoutSize;
    uint256 tradeReward;
    uint256 trueOrderSize;
}

library UniV3BuySell {
    using SafeERC20 for IERC20;

    error AddressZero();
    error InvalidPoolVersion();

    function handleBuy(
        address recipient,
        uint256 orderSize,
        uint256 minAmountOut,
        uint160 sqrtPriceLimitX96,
        address tradeReferrer,
        CoinConfig memory coinConfig,
        address currency,
        ISwapRouter swapRouter,
        IWETH weth
    ) internal returns (uint256 amountOut, uint256 tradeReward, uint256 trueOrderSize) {
        if (recipient == address(0)) {
            revert AddressZero();
        }

        // Calculate the trade reward
        tradeReward = _calculateReward(orderSize, CoinConstants.TOTAL_FEE_BPS);

        // Calculate the remaining size
        trueOrderSize = orderSize - tradeReward;

        // Handle incoming currency
        _handleIncomingCurrency(orderSize, trueOrderSize, currency, swapRouter, weth);

        // Set up the swap parameters
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: currency,
            tokenOut: address(this),
            fee: MarketConstants.LP_FEE,
            recipient: recipient,
            amountIn: trueOrderSize,
            amountOutMinimum: minAmountOut,
            sqrtPriceLimitX96: sqrtPriceLimitX96
        });

        // Execute the swap
        amountOut = ISwapRouter(swapRouter).exactInputSingle(params);

        CoinRewards.handleTradeRewards(tradeReward, tradeReferrer, coinConfig, currency, weth);
    }

    function _executeSwap(
        uint256 orderSize,
        uint256 minAmountOut,
        uint160 sqrtPriceLimitX96,
        address currency,
        ISwapRouter swapRouter
    ) internal returns (uint256 amountOut) {
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(this),
            tokenOut: currency,
            fee: MarketConstants.LP_FEE,
            recipient: address(this),
            amountIn: orderSize,
            amountOutMinimum: minAmountOut,
            sqrtPriceLimitX96: sqrtPriceLimitX96
        });

        amountOut = swapRouter.exactInputSingle(params);
    }

    function _handleRefund(uint256 beforeCoinBalance, uint256 orderSize, address recipient) internal returns (uint256 trueOrderSize) {
        uint256 afterCoinBalance = IERC20(address(this)).balanceOf(address(this));
        trueOrderSize = orderSize;

        if (afterCoinBalance > beforeCoinBalance) {
            uint256 coinRefund = afterCoinBalance - beforeCoinBalance;
            trueOrderSize -= coinRefund;
            IERC20(address(this)).safeTransfer(recipient, coinRefund);
        }
    }

    function _handlePayoutAndRewards(
        uint256 amountOut,
        address recipient,
        address tradeReferrer,
        CoinConfig memory coinConfig,
        address currency,
        IWETH weth
    ) internal returns (uint256 payoutSize, uint256 tradeReward) {
        if (currency == address(weth)) {
            weth.withdraw(amountOut);
        }

        tradeReward = _calculateReward(amountOut, CoinConstants.TOTAL_FEE_BPS);
        payoutSize = amountOut - tradeReward;

        _handlePayout(payoutSize, recipient, currency, weth);

        CoinRewards.handleTradeRewards(tradeReward, tradeReferrer, coinConfig, currency, weth);
    }

    function handleSell(
        address recipient,
        uint256 beforeCoinBalance,
        uint256 orderSize,
        uint256 minAmountOut,
        uint160 sqrtPriceLimitX96,
        address tradeReferrer,
        CoinConfig memory coinConfig,
        address currency,
        ISwapRouter swapRouter,
        IWETH weth
    ) internal returns (SellResult memory result) {
        if (recipient == address(0)) {
            revert AddressZero();
        }

        uint256 amountOut = _executeSwap(orderSize, minAmountOut, sqrtPriceLimitX96, currency, swapRouter);
        result.trueOrderSize = _handleRefund(beforeCoinBalance, orderSize, recipient);
        (result.payoutSize, result.tradeReward) = _handlePayoutAndRewards(amountOut, recipient, tradeReferrer, coinConfig, currency, weth);
    }

    /// @dev Handles incoming currency transfers for buy orders; if WETH is the currency the caller has the option to send native-ETH
    /// @param orderSize The total size of the order in the currency
    /// @param trueOrderSize The actual amount being used for the swap after fees
    function _handleIncomingCurrency(uint256 orderSize, uint256 trueOrderSize, address currency, ISwapRouter swapRouter, IWETH weth) internal {
        if (currency == address(weth) && msg.value > 0) {
            if (msg.value != orderSize) {
                revert ICoin.EthAmountMismatch();
            }

            if (msg.value < CoinConstants.MIN_ORDER_SIZE) {
                revert ICoin.EthAmountTooSmall();
            }

            IWETH(weth).deposit{value: trueOrderSize}();
            IWETH(weth).approve(address(swapRouter), trueOrderSize);
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

            IERC20(currency).approve(address(swapRouter), trueOrderSize);
        }
    }

    /// @dev Handles sending ETH and ERC20 payouts and refunds to recipients
    /// @param orderPayout The amount of currency to pay out
    /// @param recipient The address to receive the payout
    function _handlePayout(uint256 orderPayout, address recipient, address currency, IWETH weth) internal {
        if (currency == address(weth)) {
            Address.sendValue(payable(recipient), orderPayout);
        } else {
            IERC20(currency).safeTransfer(recipient, orderPayout);
        }
    }

    function _collectFees(LpPosition[] storage positions, address poolAddress) internal returns (uint256 totalAmountToken0, uint256 totalAmountToken1) {
        for (uint256 i; i < positions.length; i++) {
            // Must burn to update the collect mapping on the pool
            IUniswapV3Pool(poolAddress).burn(positions[i].tickLower, positions[i].tickUpper, 0);

            (uint256 amount0, uint256 amount1) = IUniswapV3Pool(poolAddress).collect(
                address(this),
                positions[i].tickLower,
                positions[i].tickUpper,
                type(uint128).max,
                type(uint128).max
            );

            totalAmountToken0 += amount0;
            totalAmountToken1 += amount1;
        }
    }

    /// @dev Collects and distributes accrued fees from all LP positions
    function handleMarketRewards(
        CoinConfig memory coinConfig,
        address currency,
        address poolAddress,
        LpPosition[] storage positions,
        IWETH weth,
        address doppler
    ) internal returns (ICoin.MarketRewards memory rewards) {
        address coin = address(this);
        (uint256 totalAmountToken0, uint256 totalAmountToken1) = _collectFees(positions, poolAddress);

        address token0 = currency < coin ? currency : coin;
        address token1 = currency < coin ? coin : currency;

        rewards = CoinRewards.transferBothRewards(token0, totalAmountToken0, token1, totalAmountToken1, coin, coinConfig, currency, weth, doppler);

        emit ICoin.CoinMarketRewards(coinConfig.payoutRecipient, coinConfig.platformReferrer, coinConfig.protocolRewardRecipient, currency, rewards);
    }

    function _calculateReward(uint256 amount, uint256 bps) internal pure returns (uint256) {
        return CoinRewards.calculateReward(amount, bps);
    }
}
