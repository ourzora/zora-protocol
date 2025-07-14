// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {DeterministicContractConfig} from "@zoralabs/shared-contracts/deployment/Config.sol";

// config for deploying the Sparks proxy,
// this should be the same on all chains
struct SparksDeterministicConfig {
    // address of the account that is to do the deployment
    address deploymentCaller;
    DeterministicContractConfig manager;
    DeterministicContractConfig sparks1155;
}
