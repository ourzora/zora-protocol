// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {TokenConfig} from "./ZoraSparksTypes.sol";

abstract contract SparksStorageBase {
    mapping(uint256 => TokenConfig) tokenConfigs;
    mapping(address => uint256) accountBalances;
}
