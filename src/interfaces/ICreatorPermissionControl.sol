// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

/// @notice Generic control interface for bit-based permissions-control
interface ICreatorPermissionControl {
    /// @notice Emitted when permissions are updated
    event UpdatedPermissions(uint256 indexed tokenId, address indexed user, uint256 indexed permissions);

    /// @notice Public interface to get permissions given a token id and a user address
    /// @return Returns raw permission bits
    function getPermissions(uint256 tokenId, address user) external view returns (uint256);
}
