// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {CreatorPermissionControl} from "../../src/permissions/CreatorPermissionControl.sol";

contract MockPermissionControl is CreatorPermissionControl {
    function addPermission(uint256 tokenId, address user, uint256 permissionBits) external {
        _addPermission(tokenId, user, permissionBits);
    }

    function clearPermissions(uint256 tokenId, address user) external {
        _clearPermissions(tokenId, user);
    }

    function removePermission(uint256 tokenId, address user, uint256 permissionBits) external {
        _removePermission(tokenId, user, permissionBits);
    }
}
