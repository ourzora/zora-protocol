// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {PoolConfiguration} from "../interfaces/ICoin.sol";
import {CoinLegacyMarket} from "./CoinLegacyMarket.sol";
import {CoinDopplerUniV3Market} from "./CoinDopplerUniV3Market.sol";
import {CoinConfigurationVersions} from "./CoinConfigurationVersions.sol";
import {LpPosition} from "../types/LpPosition.sol";

library CoinMarket {
    error InvalidPoolVersion();

    function setupPoolWithVersion(
        uint8 version,
        bytes memory poolConfig_,
        bool isCoinToken0,
        address weth
    ) internal pure returns (uint160 sqrtPriceX96, PoolConfiguration memory poolConfiguration) {
        if (version == CoinConfigurationVersions.LEGACY_POOL_VERSION) {
            (sqrtPriceX96, poolConfiguration) = CoinLegacyMarket.setupPool(isCoinToken0, poolConfig_, weth);
        } else if (version == CoinConfigurationVersions.DOPPLER_UNI_V3_POOL_VERSION) {
            (sqrtPriceX96, poolConfiguration) = CoinDopplerUniV3Market.setupPool(isCoinToken0, poolConfig_);
        } else {
            revert InvalidPoolVersion();
        }
    }

    function calculatePositions(bool isCoinToken0, PoolConfiguration memory poolConfiguration) internal pure returns (LpPosition[] memory positions) {
        if (poolConfiguration.version == CoinConfigurationVersions.LEGACY_POOL_VERSION) {
            positions = CoinLegacyMarket.calculatePositions(isCoinToken0, poolConfiguration);
        } else if (poolConfiguration.version == CoinConfigurationVersions.DOPPLER_UNI_V3_POOL_VERSION) {
            positions = CoinDopplerUniV3Market.calculatePositions(isCoinToken0, poolConfiguration);
        } else {
            revert InvalidPoolVersion();
        }
    }
}
