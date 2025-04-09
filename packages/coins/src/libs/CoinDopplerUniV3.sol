// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {PoolConfiguration} from "../interfaces/ICoin.sol";
import {TickMath} from "../utils/uniswap/TickMath.sol";
import {CoinConfigurationVersions} from "./CoinConfigurationVersions.sol";
import {ICoin} from "../interfaces/ICoin.sol";
import {LpPosition} from "../types/LpPosition.sol";
import {MarketConstants} from "./MarketConstants.sol";
import {FullMath} from "../utils/uniswap/FullMath.sol";
import {SqrtPriceMath} from "../utils/uniswap/SqrtPriceMath.sol";
import {LiquidityAmounts} from "../utils/uniswap/LiquidityAmounts.sol";
import {IDopplerErrors} from "../interfaces/IDopplerErrors.sol";

library CoinDopplerUniV3 {
    function setupPool(bool isCoinToken0, bytes memory poolConfig_) internal pure returns (uint160 sqrtPriceX96, PoolConfiguration memory poolConfiguration) {
        (, , int24 tickLower_, int24 tickUpper_, uint16 numDiscoveryPositions_, uint256 maxDiscoverySupplyShare_) = abi.decode(
            poolConfig_,
            (uint8, address, int24, int24, uint16, uint256)
        );

        require(numDiscoveryPositions_ > 1 && numDiscoveryPositions_ <= 200, IDopplerErrors.NumDiscoveryPositionsOutOfRange());

        if (maxDiscoverySupplyShare_ > MarketConstants.WAD) {
            revert IDopplerErrors.MaxShareToBeSoldExceeded(maxDiscoverySupplyShare_, MarketConstants.WAD);
        }

        int24 savedTickLower = isCoinToken0 ? tickLower_ : -tickUpper_;
        int24 savedTickUpper = isCoinToken0 ? tickUpper_ : -tickLower_;

        sqrtPriceX96 = TickMath.getSqrtPriceAtTick(isCoinToken0 ? savedTickLower : savedTickUpper);

        poolConfiguration = PoolConfiguration({
            version: CoinConfigurationVersions.DOPPLER_UNI_V3_POOL_VERSION,
            tickLower: savedTickLower,
            tickUpper: savedTickUpper,
            numPositions: numDiscoveryPositions_,
            maxDiscoverySupplyShare: maxDiscoverySupplyShare_
        });
    }

    function calculatePositions(bool isCoinToken0, PoolConfiguration memory poolConfiguration) internal pure returns (LpPosition[] memory positions) {
        positions = new LpPosition[](poolConfiguration.numPositions);

        uint256 discoverySupply = FullMath.mulDiv(MarketConstants.POOL_LAUNCH_SUPPLY, poolConfiguration.maxDiscoverySupplyShare, MarketConstants.WAD);

        (positions, discoverySupply) = calculateLogNormalDistribution(
            poolConfiguration.tickLower,
            poolConfiguration.tickUpper,
            MarketConstants.TICK_SPACING,
            isCoinToken0,
            discoverySupply,
            // Populate all positions before the last position (the tail position)
            poolConfiguration.numPositions - 1, // Only discovery positions
            positions
        );

        uint256 tailSupply = MarketConstants.POOL_LAUNCH_SUPPLY - discoverySupply;

        // Calculate the tail position (the last position in the array)
        positions[poolConfiguration.numPositions - 1] = calculateLpTail(
            poolConfiguration.tickLower,
            poolConfiguration.tickUpper,
            isCoinToken0,
            tailSupply,
            MarketConstants.TICK_SPACING
        );
    }

    /// @notice Calculates the distribution of liquidity positions across tick ranges.
    /// @dev For example, with 1000 tokens and 10 bins starting at tick 0:
    ///      - Creates positions: [0,10], [1,10], [2,10], ..., [9,10]
    ///      - Each position gets an equal share of tokens (100 tokens each)
    ///      This creates a linear distribution of liquidity across the tick range
    /// @dev Changed in DopplerUniswapV3:
    ///      - Added `LpPosition[] memory newPositions` as an input parameter, removing the internal allocation (`new LpPosition[](totalPositions + 1)`).
    ///      - Removed the calculation and accumulation of the `reserves` variable entirely.
    ///      - Return value changed from `(LpPosition[] memory, uint256)` (positions, reserves) to `(LpPosition[] memory, uint256)` (positions, totalAssetsSold).
    /// @param tickLower The lower tick of the LP range set
    /// @param tickUpper The upper tick of the LP range set
    /// @param tickSpacing The tick spacing of the LP range set
    /// @param isToken0 Whether the base asset is the token0 of the pair
    /// @param discoverySupply The total supply of the base asset to be sold
    /// @param totalPositions The total number of positions in the LP range set
    /// @param newPositions The array of new positions to be created
    /// @return newPositions The array of new positions to be created
    /// @return totalAssetsSold The total assets used in the LP range set
    function calculateLogNormalDistribution(
        int24 tickLower,
        int24 tickUpper,
        int24 tickSpacing,
        bool isToken0,
        uint256 discoverySupply,
        uint16 totalPositions,
        LpPosition[] memory newPositions
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

                newPositions[i] = LpPosition({
                    tickLower: farSqrtPriceX96 < startingSqrtPriceX96 ? farTick : startingTick,
                    tickUpper: farSqrtPriceX96 < startingSqrtPriceX96 ? startingTick : farTick,
                    liquidity: liquidity
                });
            }
        }

        require(totalAssetsSold <= discoverySupply, IDopplerErrors.CannotMintZeroLiquidity());

        return (newPositions, totalAssetsSold);
    }

    /// @notice Calculates the final LP position that extends from the far tick to the pool's min/max tick
    /// @dev This position ensures price equivalence between Uniswap v2 and v3 pools beyond the LBP range
    /// @dev Changed in DopplerUniswapV3:
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
