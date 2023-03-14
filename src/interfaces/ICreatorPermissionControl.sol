// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface ICreatorPermissionControl {
    event UpdatedPermissions(uint256 indexed tokenId, address indexed user, uint256 indexed permissions);

    function getPermissions(uint256 token, address user) external view returns (uint256);
}
