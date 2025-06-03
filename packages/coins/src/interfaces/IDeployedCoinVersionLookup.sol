// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @title IDeployedCoinVersionLookup
/// @notice Interface for querying the version of a deployed coin
interface IDeployedCoinVersionLookup {
    /// @notice Gets the version for a deployed coin
    /// @param coin The address of the coin
    /// @return version The version of the coin (0 if not found)
    function getVersionForDeployedCoin(address coin) external view returns (uint8);
}
