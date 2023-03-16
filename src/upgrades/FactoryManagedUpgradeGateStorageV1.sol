// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

abstract contract FactoryManagedUpgradeGateStorageV1 {
    mapping(address => mapping(address => bool)) public isAllowedUpgrade;

    uint256[50] private __gap;
}
