// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {CreatorPermissionStorageV1} from "./CreatorPermissionStorageV1.sol";
import {ICreatorPermissionControl} from "../interfaces/ICreatorPermissionControl.sol";

contract CreatorPermissionControl is CreatorPermissionStorageV1, ICreatorPermissionControl {
    function _hasPermission(uint256 tokenId, address user, uint256 permissionBits) internal view returns (bool) {
        return permissions[tokenId][user] & permissionBits > 0;
    }

    /// @notice return the permission bits for a given user and token combo
    function getPermissions(uint256 token, address user) external view returns (uint256) {
        return permissions[token][user];
    }

    function _addPermission(uint256 tokenId, address user, uint256 permissionBits) internal {
        uint256 tokenPermissions = permissions[tokenId][user];
        tokenPermissions |= permissionBits;
        permissions[tokenId][user] = tokenPermissions;
        emit UpdatedPermissions(tokenId, user, tokenPermissions);
    }

    function _clearPermissions(uint256 tokenId, address user) internal {
        permissions[tokenId][user] = 0;
        emit UpdatedPermissions(tokenId, user, 0);
    }

    function _removePermission(uint256 tokenId, address user, uint256 permissionBits) internal {
        uint256 tokenPermissions = permissions[tokenId][user];
        tokenPermissions &= ~permissionBits;
        permissions[tokenId][user] = tokenPermissions;
        emit UpdatedPermissions(tokenId, user, tokenPermissions);
    }
}
