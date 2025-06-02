// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {PoolConfiguration} from "../interfaces/ICoin.sol";
import {CoinDopplerUniV3} from "./CoinDopplerUniV3.sol";
import {CoinConfigurationVersions} from "./CoinConfigurationVersions.sol";
import {LpPosition} from "../types/LpPosition.sol";
import {IUniswapV3Factory} from "../interfaces/IUniswapV3Factory.sol";
import {MarketConstants} from "./MarketConstants.sol";
import {IUniswapV3Pool} from "../interfaces/IUniswapV3Pool.sol";
import {ICoin} from "../interfaces/ICoin.sol";
import {CoinCommon} from "./CoinCommon.sol";
struct UniV3Config {
    address weth;
    address v3Factory;
    address airlock;
    address swapRouter;
}

struct CoinV3Config {
    address currency;
    PoolConfiguration poolConfiguration;
    address poolAddress;
}

library CoinSetupV3 {
    /// @dev Deploys the Uniswap V3 pool and mints initial liquidity based on the pool configuration
    function deployLiquidity(LpPosition[] memory positions, address poolAddress) internal {
        // Calculate and mint positions
        _mintPositions(positions, poolAddress);
    }

    /// @dev Mints the calculated liquidity positions into the Uniswap V3 pool
    function _mintPositions(LpPosition[] memory lbpPositions, address poolAddress) internal {
        for (uint256 i; i < lbpPositions.length; i++) {
            IUniswapV3Pool(poolAddress).mint(address(this), lbpPositions[i].tickLower, lbpPositions[i].tickUpper, lbpPositions[i].liquidity, "");
        }
    }

    /// @dev Creates the Uniswap V3 pool for the coin/currency pair
    function createV3Pool(address coin, address currency, bool isCoinToken0, uint160 sqrtPriceX96, address v3Factory) internal returns (address pool) {
        address token0 = isCoinToken0 ? coin : currency;
        address token1 = isCoinToken0 ? currency : coin;
        pool = IUniswapV3Factory(v3Factory).createPool(token0, token1, MarketConstants.LP_FEE);

        // This pool should be new, if it has already been initialized
        // then we will fail the creation step prompting the user to try again.
        IUniswapV3Pool(pool).initialize(sqrtPriceX96);
    }
}
