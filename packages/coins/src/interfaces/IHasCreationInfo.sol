// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @title IHasCreationInfo
/// @notice Interface for coins that support launch fee functionality
/// @dev Legacy coins that don't implement this interface will use the normal LP fee
interface IHasCreationInfo {
    /// @notice Returns creation info for the coin used by the launch fee calculation
    /// @return creationTimestamp The block.timestamp when the coin was initialized
    /// @return isDeploying True if the coin is being deployed (transient), false otherwise
    function creationInfo() external view returns (uint256 creationTimestamp, bool isDeploying);
}
