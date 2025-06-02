// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @notice The configuration of the pool
/// @dev This is used to configure the pool's liquidity positions
struct PoolConfiguration {
    uint8 version;
    uint16 numPositions;
    uint24 fee;
    int24 tickSpacing;
    uint16[] numDiscoveryPositions;
    int24[] tickLower;
    int24[] tickUpper;
    uint256[] maxDiscoverySupplyShare;
}
