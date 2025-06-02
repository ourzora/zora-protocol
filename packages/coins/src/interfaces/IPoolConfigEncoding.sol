// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @dev contract to enable encoding pool config from the client
interface IPoolConfigEncoding {
    function encodeMultiCurvePoolConfig(
        uint8 version,
        address currency,
        int24[] memory tickLower,
        int24[] memory tickUpper,
        uint16[] memory numDiscoveryPositions,
        uint256[] memory maxDiscoverySupplyShare
    ) external pure returns (bytes memory);
}
