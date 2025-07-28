// SPDX-License-Identifier: ZORA-DELAYED-OSL-v1
// This software is licensed under the Zora Delayed Open Source License.
// Under this license, you may use, copy, modify, and distribute this software for
// non-commercial purposes only. Commercial use and competitive products are prohibited
// until the "Open Date" (3 years from first public distribution or earlier at Zora's discretion),
// at which point this software automatically becomes available under the MIT License.
// Full license terms available at: https://docs.zora.co/coins/license
pragma solidity ^0.8.23;

import {CoinConstants} from "./CoinConstants.sol";

library CoinConfigurationVersions {
    uint8 constant LEGACY_POOL_VERSION = 1;
    uint8 constant DOPPLER_UNI_V3_POOL_VERSION = 2;
    uint8 constant DOPPLER_MULTICURVE_UNI_V4_POOL_VERSION = 4;

    function getVersion(bytes memory poolConfig) internal pure returns (uint8 version) {
        return (version) = abi.decode(poolConfig, (uint8));
    }

    function isV3(uint8 version) internal pure returns (bool) {
        return version == DOPPLER_UNI_V3_POOL_VERSION || version == LEGACY_POOL_VERSION;
    }

    function isV4(uint8 version) internal pure returns (bool) {
        return version == DOPPLER_MULTICURVE_UNI_V4_POOL_VERSION;
    }

    function decodeVersionAndCurrency(bytes memory poolConfig) internal pure returns (uint8 version, address currency) {
        (version, currency) = abi.decode(poolConfig, (uint8, address));
    }

    function decodeVanillaUniV4(bytes memory poolConfig) internal pure returns (uint8 version, address currency, int24 tickLower_) {
        (version, currency, tickLower_) = abi.decode(poolConfig, (uint8, address, int24));
    }

    function encodeDopplerMultiCurveUniV4(
        address currency,
        int24[] memory tickLower_,
        int24[] memory tickUpper_,
        uint16[] memory numDiscoveryPositions_,
        uint256[] memory maxDiscoverySupplyShare_
    ) internal pure returns (bytes memory) {
        return abi.encode(DOPPLER_MULTICURVE_UNI_V4_POOL_VERSION, currency, tickLower_, tickUpper_, numDiscoveryPositions_, maxDiscoverySupplyShare_);
    }

    function decodeDopplerMultiCurveUniV4(
        bytes memory poolConfig
    )
        internal
        pure
        returns (
            uint8 version,
            address currency,
            int24[] memory tickLower_,
            int24[] memory tickUpper_,
            uint16[] memory numDiscoveryPositions_,
            uint256[] memory maxDiscoverySupplyShare_
        )
    {
        (version, currency, tickLower_, tickUpper_, numDiscoveryPositions_, maxDiscoverySupplyShare_) = abi.decode(
            poolConfig,
            (uint8, address, int24[], int24[], uint16[], uint256[])
        );
    }

    function defaultDopplerMultiCurveUniV4(address currency) internal pure returns (bytes memory) {
        int24[] memory tickLower = new int24[](2);
        int24[] memory tickUpper = new int24[](2);
        uint16[] memory numDiscoveryPositions = new uint16[](2);
        uint256[] memory maxDiscoverySupplyShare = new uint256[](2);

        // todo: configure defaults
        // Curve 1
        tickLower[0] = -328_000;
        tickUpper[0] = -300_000;
        numDiscoveryPositions[0] = 2;
        maxDiscoverySupplyShare[0] = 0.1e18;

        // Curve 2
        tickLower[1] = -200_000;
        tickUpper[1] = -100_000;
        numDiscoveryPositions[1] = 2;
        maxDiscoverySupplyShare[1] = 0.1e18;

        return encodeDopplerMultiCurveUniV4(currency, tickLower, tickUpper, numDiscoveryPositions, maxDiscoverySupplyShare);
    }

    function defaultConfig(address currency) internal pure returns (bytes memory) {
        return defaultDopplerMultiCurveUniV4(currency);
    }
}
