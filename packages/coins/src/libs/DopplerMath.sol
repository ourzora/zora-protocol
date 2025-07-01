// SPDX-License-Identifier: ZORA-DELAYED-OSL-v1
// This software is licensed under the Zora Delayed Open Source License.
// Under this license, you may use, copy, modify, and distribute this software for
// non-commercial purposes only. Commercial use and competitive products are prohibited
// until the "Open Date" (3 years from first public distribution or earlier at Zora's discretion),
// at which point this software automatically becomes available under the MIT License.
// Full license terms available at: https://docs.zora.co/coins/license
pragma solidity ^0.8.24;

import {IDopplerErrors} from "../interfaces/IDopplerErrors.sol";
import {TickMath} from "../utils/uniswap/TickMath.sol";
import {FullMath} from "../utils/uniswap/FullMath.sol";
import {SqrtPriceMath} from "../utils/uniswap/SqrtPriceMath.sol";
import {LiquidityAmounts} from "../utils/uniswap/LiquidityAmounts.sol";
import {LpPosition} from "../types/LpPosition.sol";
import {MarketConstants} from "./MarketConstants.sol";

/// @author Whetstone Research
/// @notice Calculates liquidity provisioning with Uniswap v3
library DopplerMath {
    /// @notice Calculates the distribution of liquidity positions across tick ranges.
    /// @dev For example, with 1000 tokens and 10 bins starting at tick 0:
    ///      - Creates positions: [0,10], [1,10], [2,10], ..., [9,10]
    ///      - Each position gets an equal share of tokens (100 tokens each)
    ///      This creates a linear distribution of liquidity across the tick range
    /// @dev Changed from UniswapV3Initializer:
    ///      - Added `LpPosition[] memory newPositions` as an input parameter, removing the internal allocation (`new LpPosition[](totalPositions + 1)`).
    ///      - Added `uint256 positionOffset` as an input parameter to specify the starting write index within the `newPositions` array.
    ///      - Removed the calculation and accumulation of the `reserves` variable entirely.
    ///      - Return value changed from `(LpPosition[] memory, uint256)` (positions, reserves) to `(LpPosition[] memory, uint256)` (positions, totalAssetsSold).
    /// @param tickLower The lower tick of the LP range set
    /// @param tickUpper The upper tick of the LP range set
    /// @param tickSpacing The tick spacing of the LP range set
    /// @param isToken0 Whether the base asset is the token0 of the pair
    /// @param discoverySupply The total supply of the base asset to be sold
    /// @param totalPositions The total number of positions in the LP range set
    /// @param newPositions The array of new positions to be created
    /// @param positionOffset The starting index to update `newPositions`
    /// @return newPositions The array of new positions to be created
    /// @return totalAssetsSold The total assets used in the LP range set
    function calculateLogNormalDistribution(
        int24 tickLower,
        int24 tickUpper,
        int24 tickSpacing,
        bool isToken0,
        uint256 discoverySupply,
        uint16 totalPositions,
        LpPosition[] memory newPositions,
        uint256 positionOffset
    ) internal pure returns (LpPosition[] memory, uint256) {
        int24 farTick = isToken0 ? tickUpper : tickLower;
        int24 closeTick = isToken0 ? tickLower : tickUpper;

        int24 spread = tickUpper - tickLower;

        uint160 farSqrtPriceX96 = TickMath.getSqrtPriceAtTick(farTick);
        uint256 amountPerPosition = FullMath.mulDiv(discoverySupply, MarketConstants.WAD, totalPositions * MarketConstants.WAD);
        uint256 totalAssetsSold;

        for (uint256 i; i < totalPositions; i++) {
            // calculate the ticks position * 1/n to optimize the division
            int24 startingTick = isToken0
                ? closeTick + int24(uint24(FullMath.mulDiv(i, uint256(uint24(spread)), totalPositions)))
                : closeTick - int24(uint24(FullMath.mulDiv(i, uint256(uint24(spread)), totalPositions)));

            // round the tick to the nearest bin
            startingTick = alignTickToTickSpacing(isToken0, startingTick, tickSpacing);

            if (startingTick != farTick) {
                uint160 startingSqrtPriceX96 = TickMath.getSqrtPriceAtTick(startingTick);

                // if discoverySupply is 0, we skip the liquidity calculation as we are burning max liquidity
                // in each position
                uint128 liquidity;
                if (discoverySupply != 0) {
                    liquidity = isToken0
                        ? LiquidityAmounts.getLiquidityForAmount0(startingSqrtPriceX96, farSqrtPriceX96, amountPerPosition)
                        : LiquidityAmounts.getLiquidityForAmount1(farSqrtPriceX96, startingSqrtPriceX96, amountPerPosition);

                    totalAssetsSold += (
                        isToken0
                            ? SqrtPriceMath.getAmount0Delta(startingSqrtPriceX96, farSqrtPriceX96, liquidity, true)
                            : SqrtPriceMath.getAmount1Delta(farSqrtPriceX96, startingSqrtPriceX96, liquidity, true)
                    );
                }

                int24 posFinalTickLower;
                int24 posFinalTickUpper;
                if (farSqrtPriceX96 < startingSqrtPriceX96) {
                    posFinalTickLower = farTick;
                    posFinalTickUpper = startingTick;
                } else {
                    posFinalTickLower = startingTick;
                    posFinalTickUpper = farTick;
                }

                newPositions[positionOffset + i] = LpPosition({tickLower: posFinalTickLower, tickUpper: posFinalTickUpper, liquidity: liquidity});
            }
        }

        require(totalAssetsSold <= discoverySupply, IDopplerErrors.CannotMintZeroLiquidity());

        return (newPositions, totalAssetsSold);
    }

    /// @notice Calculates the final LP position that extends from the far tick to the pool's min/max tick
    /// @dev This position ensures price equivalence between Uniswap v2 and v3 pools beyond the LBP range
    /// @dev Changed from UniswapV3Initializer:
    ///      - Removed parameters: `id`, `reserves`
    ///      - Liquidity calculation is based *solely* on the provided `tailSupply` within the calculated tail tick range using `LiquidityAmounts.getLiquidityForAmount0` or `getLiquidityForAmount1`.
    function calculateLpTail(
        int24 tickLower,
        int24 tickUpper,
        bool isToken0,
        uint256 tailSupply,
        int24 tickSpacing
    ) internal pure returns (LpPosition memory lpTail) {
        int24 posTickLower = isToken0 ? tickUpper : alignTickToTickSpacing(false, TickMath.MIN_TICK, tickSpacing);
        int24 posTickUpper = isToken0 ? alignTickToTickSpacing(true, TickMath.MAX_TICK, tickSpacing) : tickLower;

        require(posTickLower < posTickUpper, IDopplerErrors.InvalidTickRangeMisordered(posTickLower, posTickUpper));

        // Calculate the sqrtPrices for the tail range boundaries
        uint160 sqrtPriceA = TickMath.getSqrtPriceAtTick(posTickLower);
        uint160 sqrtPriceB = TickMath.getSqrtPriceAtTick(posTickUpper);

        // Calculate liquidity only based on the tail range supply
        uint128 lpTailLiquidity = isToken0
            ? LiquidityAmounts.getLiquidityForAmount0(sqrtPriceA, sqrtPriceB, tailSupply)
            : LiquidityAmounts.getLiquidityForAmount1(sqrtPriceA, sqrtPriceB, tailSupply);

        lpTail = LpPosition({tickLower: posTickLower, tickUpper: posTickUpper, liquidity: lpTailLiquidity});
    }

    /// @notice Aligns a tick to the nearest tick spacing
    /// @dev The tickSpacing parameter cannot be zero
    /// @param isToken0 Whether the base asset is the token0 of the pair
    /// @param tick The tick to align
    /// @param tickSpacing The tick spacing of the pair
    /// @return alignedTick The aligned tick
    function alignTickToTickSpacing(bool isToken0, int24 tick, int24 tickSpacing) internal pure returns (int24) {
        if (isToken0) {
            // Round down if isToken0
            if (tick < 0) {
                // If the tick is negative, we round up (negatively) the negative result to round down
                return ((tick - tickSpacing + 1) / tickSpacing) * tickSpacing;
            } else {
                // Else if positive, we simply round down
                return (tick / tickSpacing) * tickSpacing;
            }
        } else {
            // Round up if isToken1
            if (tick < 0) {
                // If the tick is negative, we round down the negative result to round up
                return (tick / tickSpacing) * tickSpacing;
            } else {
                // Else if positive, we simply round up
                return ((tick + tickSpacing - 1) / tickSpacing) * tickSpacing;
            }
        }
    }
}
