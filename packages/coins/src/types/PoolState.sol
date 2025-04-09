// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @notice The state of the pool configuration, as a doppler configuration
struct PoolState {
    /// @notice The address of the base asset
    address asset;
    /// @notice The address of the currency to trade the base asset for
    address numeraire;
    /// @notice The lower tick of the LP range set
    int24 tickLower;
    /// @notice The upper tick of the LP range set
    int24 tickUpper;
    /// @notice The number of positions in the LP range set
    uint16 numPositions;
    /// @notice Whether the pool is initialized (true for this implementation)
    bool isInitialized;
    /// @notice Whether the pool is exited to a market (false for this implementation)
    bool isExited;
    /// @notice The maximum share to be sold – the size of the discovery supply
    uint256 maxShareToBeSold;
    /// @notice The total tokens on the bonding curve
    uint256 totalTokensOnBondingCurve;
}
