// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";

import {ImmutableCreate2FactoryUtils} from "@zoralabs/shared-contracts/utils/ImmutableCreate2FactoryUtils.sol";
import {ProxyDeployerScript, DeterministicDeployerAndCaller, DeterministicContractConfig} from "@zoralabs/shared-contracts/deployment/ProxyDeployerScript.sol";
import {ZoraFactory} from "../src/proxy/ZoraFactory.sol";

contract GenerateDeterministicParams is ProxyDeployerScript {
    function mineForZoraAddress(DeterministicDeployerAndCaller deployer, address caller) private returns (DeterministicContractConfig memory config) {
        // get proxy creation code
        bytes memory initCode = deployer.proxyCreationCode(type(ZoraFactory).creationCode);
        bytes32 initCodeHash = keccak256(initCode);

        // uupsProxyDeployer is deployer
        (bytes32 salt, address expectedAddress) = mineSalt(address(deployer), initCodeHash, "7777777", caller);

        console2.log("salt");
        console2.log(vm.toString(salt));

        config.salt = salt;
        config.deployedAddress = expectedAddress;
        config.creationCode = initCode;
        config.constructorArgs = deployer.proxyConstructorArgs();
        config.contractName = "Zora";
        config.deploymentCaller = caller;
    }

    function run() public {
        address caller = vm.envAddress("DEPLOYER");

        vm.startBroadcast();

        // create a proxy deployer, which we can use to generate deterministic addresses and corresponding params
        DeterministicDeployerAndCaller deployer = createOrGetDeployerAndCaller();

        vm.stopBroadcast();

        DeterministicContractConfig memory zoraConfig = mineForZoraAddress(deployer, caller);
        saveDeterministicContractConfig(zoraConfig, "zoraFactory");
    }
}
