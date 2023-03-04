// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface ICreatorPermissionControl {
    event UpdatedPermissions(uint256 tokenId, address user, uint256 permissions);

    function getPermissions(uint256 token, address user) external view returns (uint256);
}
