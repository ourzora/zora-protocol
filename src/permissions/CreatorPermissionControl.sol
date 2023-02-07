// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {CreatorPermissionStorageV1} from "./CreatorPermissionStorageV1.sol";
import {ICreatorPermissionControl} from "../interfaces/ICreatorPermissionControl.sol";

contract CreatorPermissionControl is CreatorPermissionStorageV1, ICreatorPermissionControl {
    uint256 private MAX_INT = 2 ** 256 - 1;

    function getPermissionKey(uint256 token, address user) internal pure returns (uint256) {
        return uint256(keccak256(abi.encode(token, user)));
    }

    function _hasPermission(uint256 token, address user, uint256 permissionBits) internal view returns (bool) {
        return permissions[getPermissionKey(token, user)] & permissionBits > 0;
    }

    function getPermissions(uint256 token, address user) external view returns (uint256) {
        return permissions[getPermissionKey(token, user)];
    }

    function _addPermission(uint256 tokenId, address user, uint256 permissionBits) internal {
        uint256 permissionKey = getPermissionKey(tokenId, user);
        uint256 tokenPermissions = permissions[permissionKey];
        tokenPermissions |= permissionBits;
        permissions[permissionKey] = tokenPermissions;
        emit UpdatedPermissions(tokenId, user, tokenPermissions);
    }

    function _clearPermissions(uint256 tokenId, address user) internal {
        uint256 permissionKey = getPermissionKey(tokenId, user);
        permissions[permissionKey] = 0;
        emit UpdatedPermissions(tokenId, user, 0);
    }

    function _removePermission(uint256 tokenId, address user, uint256 permissionBits) internal {
        uint256 permissionKey = getPermissionKey(tokenId, user);
        uint256 tokenPermissions = permissions[permissionKey];
        tokenPermissions &= ~permissionBits;
        permissions[permissionKey] = tokenPermissions;
        emit UpdatedPermissions(tokenId, user, tokenPermissions);
    }
}
