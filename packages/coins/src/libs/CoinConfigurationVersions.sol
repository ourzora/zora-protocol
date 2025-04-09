// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

library CoinConfigurationVersions {
    uint8 constant LEGACY_POOL_VERSION = 1;
    uint8 constant DOPPLER_UNI_V3_POOL_VERSION = 2;

    error InvalidPoolVersion();
}
