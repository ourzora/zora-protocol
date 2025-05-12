// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {PoolConfiguration} from "../interfaces/ICoin.sol";
import {CoinDopplerUniV3} from "./CoinDopplerUniV3.sol";
import {CoinConfigurationVersions} from "./CoinConfigurationVersions.sol";
import {LpPosition} from "../types/LpPosition.sol";
import {IUniswapV3Factory} from "../interfaces/IUniswapV3Factory.sol";
import {MarketConstants} from "./MarketConstants.sol";
import {IUniswapV3Pool} from "../interfaces/IUniswapV3Pool.sol";

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
    error InvalidPoolVersion();

    function setupPool(
        bytes memory poolConfig_,
        UniV3Config memory uniswapV3Config,
        address coin
    ) internal returns (address currency, address poolAddress, PoolConfiguration memory poolConfiguration) {
        // Extract version and currency from pool config
        (uint8 version, address currency_) = abi.decode(poolConfig_, (uint8, address));

        // Store the currency, defaulting to WETH if address(0)
        currency = currency_ == address(0) ? uniswapV3Config.weth : currency_;

        // Sort token addresses for Uniswap V3 pool creation
        bool isCoinToken0 = _sortTokens(coin, currency);
        address token0 = isCoinToken0 ? coin : currency;
        address token1 = isCoinToken0 ? currency : coin;

        // Configure the pool with appropriate version
        uint160 sqrtPriceX96;
        (sqrtPriceX96, poolConfiguration) = setupPoolWithVersion(version, poolConfig_, isCoinToken0, uniswapV3Config.weth);

        // Create the pool
        poolAddress = _createPool(token0, token1, sqrtPriceX96, uniswapV3Config.v3Factory);
    }

    /// @dev Deploys the Uniswap V3 pool and mints initial liquidity based on the pool configuration
    function deployLiquidity(address coin, address currency, PoolConfiguration memory poolConfiguration, address poolAddress) internal {
        // Calculate and mint positions
        LpPosition[] memory positions = calculatePositions(coin, currency, poolConfiguration);
        _mintPositions(positions, poolAddress);
    }

    // Helper function to sort tokens and determine if coin is token0
    function _sortTokens(address coin, address currency) private pure returns (bool isCoinToken0) {
        return coin < currency;
    }

    function setupPoolWithVersion(
        uint8 version,
        bytes memory poolConfig_,
        bool isCoinToken0,
        address weth
    ) internal pure returns (uint160 sqrtPriceX96, PoolConfiguration memory poolConfiguration) {
        if (version == CoinConfigurationVersions.DOPPLER_UNI_V3_POOL_VERSION) {
            (sqrtPriceX96, poolConfiguration) = CoinDopplerUniV3.setupPool(isCoinToken0, poolConfig_);
        } else {
            revert InvalidPoolVersion();
        }
    }

    function calculatePositions(
        address coin,
        address currency,
        PoolConfiguration memory poolConfiguration
    ) internal pure returns (LpPosition[] memory positions) {
        // Create the pool
        bool isCoinToken0 = _sortTokens(coin, currency);
        if (poolConfiguration.version == CoinConfigurationVersions.DOPPLER_UNI_V3_POOL_VERSION) {
            positions = CoinDopplerUniV3.calculatePositions(isCoinToken0, poolConfiguration);
        } else {
            revert InvalidPoolVersion();
        }
    }

    /// @dev Mints the calculated liquidity positions into the Uniswap V3 pool
    function _mintPositions(LpPosition[] memory lbpPositions, address poolAddress) internal {
        for (uint256 i; i < lbpPositions.length; i++) {
            IUniswapV3Pool(poolAddress).mint(address(this), lbpPositions[i].tickLower, lbpPositions[i].tickUpper, lbpPositions[i].liquidity, "");
        }
    }

    /// @dev Creates the Uniswap V3 pool for the coin/currency pair
    function _createPool(address token0, address token1, uint160 sqrtPriceX96, address v3Factory) internal returns (address pool) {
        pool = IUniswapV3Factory(v3Factory).createPool(token0, token1, MarketConstants.LP_FEE);

        // This pool should be new, if it has already been initialized
        // then we will fail the creation step prompting the user to try again.
        IUniswapV3Pool(pool).initialize(sqrtPriceX96);
    }
}
