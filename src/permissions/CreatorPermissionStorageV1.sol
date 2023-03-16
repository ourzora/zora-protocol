// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

contract CreatorPermissionStorageV1 {
    mapping(uint256 => mapping(address => uint256)) public permissions;

    uint256[50] private ___gap;
}
