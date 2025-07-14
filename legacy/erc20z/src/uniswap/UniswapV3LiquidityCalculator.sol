// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {TickMath} from "./TickMath.sol";
import {FullMath} from "./FullMath.sol";
import {LiquidityAmounts} from "./LiquidityAmounts.sol";

/// @notice This is a helper library for ZORA and not from Uniswap Source
/// @dev Used to calculate the liquidity for the given specific WETH/ERC20Z token pair design
library UniswapV3LiquidityCalculator {
    uint160 internal constant SQRT_PRICE_X96_WETH_0 = 7520004393919240427432298151936;
    uint160 internal constant SQRT_PRICE_X96_ERC20Z_0 = 834720487725035753950589079;

    int24 internal constant TICK_LOWER = -887200;
    int24 internal constant TICK_UPPER = 887200;

    uint24 internal constant FEE = 10000;

    function calculateLiquidityAmounts(
        address weth,
        uint256 wethAmount,
        address erc20z,
        uint256 erc20Amount
    ) internal pure returns (address token0, address token1, uint256 amount0, uint256 amount1, uint128 liquidity) {
        token0 = weth < erc20z ? weth : erc20z;
        token1 = weth < erc20z ? erc20z : weth;

        uint160 sqrtRatioX96 = (token0 == weth) ? SQRT_PRICE_X96_WETH_0 : SQRT_PRICE_X96_ERC20Z_0;
        uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(TickMath.MIN_TICK);
        uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(TickMath.MAX_TICK);

        (uint256 amount0Desired, uint256 amount1Desired) = token0 == weth ? (wethAmount, erc20Amount) : (erc20Amount, wethAmount);

        liquidity = LiquidityAmounts.getLiquidityForAmounts(sqrtRatioX96, sqrtRatioAX96, sqrtRatioBX96, amount0Desired, amount1Desired);

        (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(sqrtRatioX96, sqrtRatioAX96, sqrtRatioBX96, liquidity);
    }
}
