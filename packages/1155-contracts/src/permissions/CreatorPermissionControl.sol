// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {CreatorPermissionStorageV1} from "./CreatorPermissionStorageV1.sol";
import {ICreatorPermissionControl} from "../interfaces/ICreatorPermissionControl.sol";

/// Imagine. Mint. Enjoy.
/// @author @iainnash / @tbtstl
contract CreatorPermissionControl is CreatorPermissionStorageV1, ICreatorPermissionControl {
    /// @notice Check if the user has any of the given permissions
    /// @dev if multiple permissions are passed in this checks for any one of those permissions
    /// @return true or false if any of the passed in permissions apply
    function _hasAnyPermission(uint256 tokenId, address user, uint256 permissionBits) internal view returns (bool) {
        // Does a bitwise and checks if any of those permissions match
        return permissions[tokenId][user] & permissionBits > 0;
    }

    /// @notice Check if the user has all of the given permissions
    /// @dev if multiple permissions are passed in this checks for any one of those permissions
    /// @return true or false if any of the passed in permissions apply
    function _hasAllPermissions(uint256 tokenId, address user, uint256 permissionBits) internal view returns (bool) {
        // Does a bitwise and checks if all of those permissions match
        return permissions[tokenId][user] & permissionBits == permissionBits;
    }

    /// @notice addPermission – internal function to add a set of permission bits to a user
    /// @param tokenId token id to add the permission to (0 indicates contract-wide add)
    /// @param user user to update permissions for
    /// @param permissionBits bits to add permissions to
    function _addPermission(uint256 tokenId, address user, uint256 permissionBits) internal {
        uint256 tokenPermissions = permissions[tokenId][user];
        tokenPermissions |= permissionBits;
        permissions[tokenId][user] = tokenPermissions;
        emit UpdatedPermissions(tokenId, user, tokenPermissions);
    }

    /// @notice _clearPermission clear permissions for user
    /// @param tokenId token id to clear permission from (0 indicates contract-wide action)
    function _clearPermissions(uint256 tokenId, address user) internal {
        permissions[tokenId][user] = 0;
        emit UpdatedPermissions(tokenId, user, 0);
    }

    /// @notice _removePermission removes permissions for user
    /// @param tokenId token id to clear permission from (0 indicates contract-wide action)
    /// @param user user to manage permissions for
    /// @param permissionBits set of permission bits to remove
    function _removePermission(uint256 tokenId, address user, uint256 permissionBits) internal {
        uint256 tokenPermissions = permissions[tokenId][user];
        tokenPermissions &= ~permissionBits;
        permissions[tokenId][user] = tokenPermissions;
        emit UpdatedPermissions(tokenId, user, tokenPermissions);
    }
}
