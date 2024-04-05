// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {TokenConfig} from "./ZoraMintsTypes.sol";

abstract contract MintsStorageBase {
    mapping(uint256 => TokenConfig) tokenConfigs;
    mapping(address => uint256) accountBalances;
}
