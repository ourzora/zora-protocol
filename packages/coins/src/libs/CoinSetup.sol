// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {PoolConfigurationV4} from "../interfaces/ICoin.sol";
import {CoinConfigurationVersions} from "./CoinConfigurationVersions.sol";
import {ICoin} from "../interfaces/ICoin.sol";
import {CoinCommon} from "./CoinCommon.sol";
import {MarketConstants} from "./MarketConstants.sol";
import {TickMath} from "../utils/uniswap/TickMath.sol";
import {IPoolManager, PoolKey, Currency, IHooks} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {MarketConstants} from "./MarketConstants.sol";
import {LpPosition} from "../types/LpPosition.sol";
import {CoinDopplerMultiCurve, PoolConfiguration} from "./CoinDopplerMultiCurve.sol";
import {CoinDopplerUniV3} from "./CoinDopplerUniV3.sol";

library CoinSetup {
    function generatePoolConfig(
        address coin,
        bytes memory poolConfig_
    ) internal pure returns (uint8 version, address currency, uint160 sqrtPriceX96, bool isCoinToken0, PoolConfiguration memory poolConfiguration) {
        // Extract version and currency from pool config
        (version, currency) = CoinConfigurationVersions.decodeVersionAndCurrency(poolConfig_);

        isCoinToken0 = CoinCommon.sortTokens(coin, currency);

        (sqrtPriceX96, poolConfiguration) = setupPoolWithVersion(version, poolConfig_, isCoinToken0);
    }

    function buildPoolKey(address coin, address currency, bool isCoinToken0, IHooks hooks) internal pure returns (PoolKey memory poolKey) {
        Currency currency0 = isCoinToken0 ? Currency.wrap(coin) : Currency.wrap(currency);
        Currency currency1 = isCoinToken0 ? Currency.wrap(currency) : Currency.wrap(coin);

        poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: MarketConstants.LP_FEE_V4,
            tickSpacing: MarketConstants.TICK_SPACING,
            hooks: hooks
        });
    }

    function setupPoolWithVersion(
        uint8 version,
        bytes memory poolConfig_,
        bool isCoinToken0
    ) internal pure returns (uint160 sqrtPriceX96, PoolConfiguration memory poolConfiguration) {
        if (version == CoinConfigurationVersions.DOPPLER_UNI_V3_POOL_VERSION) {
            (sqrtPriceX96, poolConfiguration) = CoinDopplerUniV3.setupPool(isCoinToken0, poolConfig_);
        } else if (version == CoinConfigurationVersions.DOPPLER_MULTICURVE_UNI_V4_POOL_VERSION) {
            (sqrtPriceX96, poolConfiguration) = CoinDopplerMultiCurve.setupPool(isCoinToken0, poolConfig_);
        } else {
            revert ICoin.InvalidPoolVersion();
        }
    }
}
