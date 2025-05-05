// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

// config for the determinstic proxy deployer, which should have the same config on all chains.
// this should be the same on all chains
struct ProxyDeployerConfig {
    bytes creationCode;
    bytes32 salt;
    address deployedAddress;
}

struct DeterministicContractConfig {
    // salt used to determinstically deploy the contract
    bytes32 salt;
    // code to create the contract
    bytes creationCode;
    // expected address
    address deployedAddress;
    // name of the contract, used for verification
    string contractName;
    // constructor args, used for verification
    bytes constructorArgs;
    // account that is to do the deployment
    address deploymentCaller;
}
