// SPDX-License-Identifier: ZORA-DELAYED-OSL-v1
// This software is licensed under the Zora Delayed Open Source License.
// Under this license, you may use, copy, modify, and distribute this software for
// non-commercial purposes only. Commercial use and competitive products are prohibited
// until the "Open Date" (3 years from first public distribution or earlier at Zora's discretion),
// at which point this software automatically becomes available under the MIT License.
// Full license terms available at: https://docs.zora.co/coins/license
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
