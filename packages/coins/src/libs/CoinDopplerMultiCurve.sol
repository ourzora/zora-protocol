// SPDX-License-Identifier: ZORA-DELAYED-OSL-v1
// This software is licensed under the Zora Delayed Open Source License.
// Under this license, you may use, copy, modify, and distribute this software for
// non-commercial purposes only. Commercial use and competitive products are prohibited
// until the "Open Date" (3 years from first public distribution or earlier at Zora's discretion),
// at which point this software automatically becomes available under the MIT License.
// Full license terms available at: https://docs.zora.co/coins/license
pragma solidity ^0.8.23;

import {PoolConfiguration} from "../interfaces/ICoin.sol";
import {CoinConfigurationVersions} from "./CoinConfigurationVersions.sol";
import {LpPosition} from "../types/LpPosition.sol";
import {MarketConstants} from "./MarketConstants.sol";
import {FullMath} from "../utils/uniswap/FullMath.sol";
import {TickMath} from "../utils/uniswap/TickMath.sol";
import {IDopplerErrors} from "../interfaces/IDopplerErrors.sol";
import {DopplerMath} from "./DopplerMath.sol";

library CoinDopplerMultiCurve {
    error ArrayLengthMismatch();
    error ZeroDiscoveryPositions();
    error ZeroDiscoverySupplyShare();
    error InvalidTickRangeMisordered(int24 tickLower, int24 tickUpper);
    error ConfigTickLowerMustBeLessThanTickUpper();

    /**
     * @notice Configures multi-curve liquidity based on the provided parameters.
     * @param isCoinToken0 A boolean indicating if the coin is token0 (true) or token1 (false) in the pair.
     *                     This affects tick ordering and price calculations.
     * @param poolConfig_ ABI encoded data containing the pool configuration parameters.
     *                    It is expected to be encoded in the following order:
     *                    - version (uint8): The version of the pool configuration.
     *                                     (e.g., 2 for UniswapV3, 4 for Doppler/Uniswap V4).
     *                    - currency (address): The address of the currency token (e.g., WETH) paired with the coin.
     *                    - tickLower (int24[]): An array of lower tick boundaries for each liquidity curve.
     *                    - tickUpper (int24[]): An array of upper tick boundaries for each liquidity curve.
     *                    - numDiscoveryPositions (uint16[]): An array specifying the number of discrete liquidity
     *                                                      positions within each curve's discovery phase.
     *                    - maxDiscoverySupplyShare (uint256[]): An array of WAD-scaled values (1e18) representing
     *                                                           the maximum share of the coin's total supply
     *                                                           allocated to each curve's discovery phase.
     * @return sqrtPriceX96 The initial square root price of the pool, scaled to X96 format.
     * @return poolConfiguration A struct containing the configured pool parameters,
     *                           including version, number of positions, fee, tick spacing,
     *                           and arrays for discovery positions, tick boundaries, and supply shares.
     */
    function setupPool(bool isCoinToken0, bytes memory poolConfig_) internal pure returns (uint160 sqrtPriceX96, PoolConfiguration memory poolConfiguration) {
        (, , int24[] memory tickLower_, int24[] memory tickUpper_, uint16[] memory numDiscoveryPositions_, uint256[] memory maxDiscoverySupplyShare_) = abi
            .decode(poolConfig_, (uint8, address, int24[], int24[], uint16[], uint256[]));

        uint256 numCurves = tickLower_.length;
        if (numCurves != tickUpper_.length || numCurves != numDiscoveryPositions_.length || numCurves != maxDiscoverySupplyShare_.length) {
            revert ArrayLengthMismatch();
        }

        uint256 totalDiscoverySupplyShare;
        uint256 totalDiscoveryPositions;

        int24 boundryTickLower = DopplerMath.alignTickToTickSpacing(isCoinToken0, TickMath.MAX_TICK, MarketConstants.TICK_SPACING);
        int24 boundryTickUpper = DopplerMath.alignTickToTickSpacing(isCoinToken0, TickMath.MIN_TICK, MarketConstants.TICK_SPACING);

        // For each curve:
        for (uint256 i; i < numCurves; i++) {
            // Ensure a value is specified
            require(numDiscoveryPositions_[i] > 0, ZeroDiscoveryPositions());
            require(maxDiscoverySupplyShare_[i] > 0, ZeroDiscoverySupplyShare());

            // Aggregate the total discovery positions and supply across curves
            totalDiscoveryPositions += numDiscoveryPositions_[i];
            totalDiscoverySupplyShare += maxDiscoverySupplyShare_[i];

            int24 currentTickLower = DopplerMath.alignTickToTickSpacing(isCoinToken0, tickLower_[i], MarketConstants.TICK_SPACING);
            int24 currentTickUpper = DopplerMath.alignTickToTickSpacing(isCoinToken0, tickUpper_[i], MarketConstants.TICK_SPACING);

            require(currentTickLower < currentTickUpper, ConfigTickLowerMustBeLessThanTickUpper());

            // Sort the tick values based on token order
            tickLower_[i] = isCoinToken0 ? currentTickLower : -currentTickUpper;
            tickUpper_[i] = isCoinToken0 ? currentTickUpper : -currentTickLower;

            boundryTickLower = boundryTickLower < tickLower_[i] ? boundryTickLower : tickLower_[i];
            boundryTickUpper = boundryTickUpper > tickUpper_[i] ? boundryTickUpper : tickUpper_[i];
        }

        require(boundryTickLower < boundryTickUpper, InvalidTickRangeMisordered(boundryTickLower, boundryTickUpper));
        require(totalDiscoveryPositions > 1 && totalDiscoveryPositions <= 200, IDopplerErrors.NumDiscoveryPositionsOutOfRange());
        require(totalDiscoverySupplyShare < MarketConstants.WAD, IDopplerErrors.MaxShareToBeSoldExceeded(totalDiscoverySupplyShare, MarketConstants.WAD));

        sqrtPriceX96 = TickMath.getSqrtPriceAtTick(isCoinToken0 ? boundryTickLower : boundryTickUpper);

        poolConfiguration = PoolConfiguration({
            version: CoinConfigurationVersions.DOPPLER_MULTICURVE_UNI_V4_POOL_VERSION,
            numPositions: uint16(totalDiscoveryPositions + 1), // Add one for the final tail position
            fee: MarketConstants.LP_FEE_V4,
            tickSpacing: MarketConstants.TICK_SPACING,
            numDiscoveryPositions: numDiscoveryPositions_,
            tickLower: tickLower_,
            tickUpper: tickUpper_,
            maxDiscoverySupplyShare: maxDiscoverySupplyShare_
        });
    }

    /// @notice Calculates the LP positions for a given multi-curve configuration
    function calculatePositions(
        bool isCoinToken0,
        PoolConfiguration memory poolConfiguration,
        uint256 totalSupply
    ) internal pure returns (LpPosition[] memory positions) {
        positions = new LpPosition[](poolConfiguration.numPositions);

        uint256 discoverySupply;
        uint256 currentPositionOffset;
        uint256 numCurves = poolConfiguration.tickLower.length;

        for (uint256 i; i < numCurves; i++) {
            uint256 curveSupply = FullMath.mulDiv(totalSupply, poolConfiguration.maxDiscoverySupplyShare[i], MarketConstants.WAD);

            (positions, curveSupply) = DopplerMath.calculateLogNormalDistribution(
                poolConfiguration.tickLower[i],
                poolConfiguration.tickUpper[i],
                MarketConstants.TICK_SPACING,
                isCoinToken0,
                curveSupply,
                poolConfiguration.numDiscoveryPositions[i],
                positions,
                currentPositionOffset
            );

            discoverySupply += curveSupply;
            currentPositionOffset += poolConfiguration.numDiscoveryPositions[i];
        }

        uint256 tailSupply = totalSupply - discoverySupply;

        // Calculate the tail position (the last position in the array)
        positions[poolConfiguration.numPositions - 1] = DopplerMath.calculateLpTail(
            poolConfiguration.tickLower[numCurves - 1],
            poolConfiguration.tickUpper[numCurves - 1],
            isCoinToken0,
            tailSupply,
            MarketConstants.TICK_SPACING
        );
    }
}
