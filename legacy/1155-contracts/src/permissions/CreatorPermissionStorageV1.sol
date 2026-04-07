// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

/// Imagine. Mint. Enjoy.
/// @author @iainnash / @tbtstl
contract CreatorPermissionStorageV1 {
    mapping(uint256 => mapping(address => uint256)) public permissions;

    uint256[50] private __gap;
}
