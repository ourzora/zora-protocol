// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/// @notice Generic control interface for bit-based permissions-control
interface ICreatorPermissionControl {
    /// @notice Emitted when permissions are updated
    event UpdatedPermissions(uint256 indexed tokenId, address indexed user, uint256 indexed permissions);
}
