// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {PoolConfiguration, ICoin} from "../interfaces/ICoin.sol";
import {TickMath} from "../utils/uniswap/TickMath.sol";
import {MarketConstants} from "./MarketConstants.sol";
import {LiquidityAmounts} from "../utils/uniswap/LiquidityAmounts.sol";
import {LpPosition} from "../types/LpPosition.sol";
import {CoinConfigurationVersions} from "./CoinConfigurationVersions.sol";

library CoinLegacy {
    function setupPool(
        bool isCoinToken0,
        bytes memory poolConfig_,
        address weth
    ) internal pure returns (uint160 sqrtPriceX96, PoolConfiguration memory poolConfiguration) {
        (, address currency, int24 tickLower_) = abi.decode(poolConfig_, (uint8, address, int24));

        // If WETH is the pool's currency, validate the lower tick
        if ((currency == weth || currency == address(0)) && tickLower_ > MarketConstants.LP_TICK_LOWER_WETH) {
            revert ICoin.InvalidWethLowerTick();
        }

        int24 savedTickLower = isCoinToken0 ? tickLower_ : -MarketConstants.LP_TICK_UPPER;
        int24 savedTickUpper = isCoinToken0 ? MarketConstants.LP_TICK_UPPER : -tickLower_;

        sqrtPriceX96 = TickMath.getSqrtPriceAtTick(isCoinToken0 ? savedTickLower : savedTickUpper);

        poolConfiguration = PoolConfiguration({
            version: CoinConfigurationVersions.LEGACY_POOL_VERSION,
            tickLower: savedTickLower,
            tickUpper: savedTickUpper,
            numPositions: 1,
            maxDiscoverySupplyShare: 0
        });
    }

    function calculatePositions(bool isCoinToken0, PoolConfiguration memory poolConfiguration) internal pure returns (LpPosition[] memory positions) {
        positions = new LpPosition[](1);

        uint160 sqrtPriceX96 = TickMath.getSqrtPriceAtTick(isCoinToken0 ? poolConfiguration.tickLower : poolConfiguration.tickUpper);
        uint160 farSqrtPriceX96 = TickMath.getSqrtPriceAtTick(isCoinToken0 ? poolConfiguration.tickUpper : poolConfiguration.tickLower);
        uint128 liquidity = isCoinToken0
            ? LiquidityAmounts.getLiquidityForAmount0(sqrtPriceX96, farSqrtPriceX96, MarketConstants.POOL_LAUNCH_SUPPLY)
            : LiquidityAmounts.getLiquidityForAmount1(sqrtPriceX96, farSqrtPriceX96, MarketConstants.POOL_LAUNCH_SUPPLY);
        positions[0] = LpPosition({tickLower: poolConfiguration.tickLower, tickUpper: poolConfiguration.tickUpper, liquidity: liquidity});
    }
}
