// spdx-license-identifier: mit
pragma solidity ^0.8.20;

import "forge-std/Script.sol";

import {DeterministicUUPSProxyDeployer} from "@zoralabs/shared-contracts/deployment/DeterministicUUPSProxyDeployer.sol";
import {ProxyDeployerScript} from "@zoralabs/shared-contracts/deployment/ProxyDeployerScript.sol";
import {ZoraSparksManager} from "../src/ZoraSparksManager.sol";
import {ZoraSparks1155} from "../src/ZoraSparks1155.sol";
import {DeterministicContractConfig} from "@zoralabs/shared-contracts/deployment/Config.sol";
import {SparksDeploymentConfig, SparksDeterministicConfig} from "../src/deployment/SparksDeploymentConfig.sol";

/// @dev This script saves the current bytecode, and initialization parameters for the Sparks proxy,
/// which then need to be populated with a salt and expected address, which can be achieved by
/// running the printed create2crunch command.  The resulting config only needs to be generated once
/// and is reusable for all chains.
contract GenerateDeterminsticDeployment is SparksDeploymentConfig {
    function mineForProxyAddress(DeterministicUUPSProxyDeployer uupsProxyDeployer, address caller) private returns (DeterministicContractConfig memory config) {
        // get proxy creation code
        bytes memory creationCode = type(ZoraSparksManager).creationCode;
        // get the expected init code for the proxy from the uupsProxyDeployer
        bytes memory initCode = uupsProxyDeployer.proxyCreationCode(creationCode);
        bytes32 initCodeHash = keccak256(initCode);

        // uupsProxyDeployer is deployer
        address deployer = address(uupsProxyDeployer);

        (bytes32 salt, address expectedAddress) = mineSalt(deployer, initCodeHash, "7777777", caller);

        console2.log("salt");
        console2.log(vm.toString(salt));

        config.salt = salt;
        config.deployedAddress = expectedAddress;
        config.creationCode = creationCode;
        config.constructorArgs = uupsProxyDeployer.proxyConstructorArgs();
        config.contractName = "ZoraSparksManager";
        config.deploymentCaller = caller;
    }

    function mineForSparks1155Address(address sparksManagerAddress) private returns (DeterministicContractConfig memory config) {
        // sparks 1155 is created from the zora sparks manager impl, without any arguments
        bytes memory creationCode = type(ZoraSparks1155).creationCode;
        bytes32 initCodeHash = keccak256(creationCode);
        // sparks manager is deployer
        (bytes32 salt, address expectedAddress) = mineSalt(sparksManagerAddress, initCodeHash, "7777777", address(0));

        config.salt = salt;
        config.deployedAddress = expectedAddress;
        config.creationCode = creationCode;
        // no constructor args for sparks 1155
        config.contractName = "ZoraSparks1155";
    }

    function run() public {
        address deployer = vm.envAddress("DEPLOYER");

        vm.startBroadcast();

        // create a proxy deployer, which we can use to generated deterministic addresses and corresponding params.
        // proxy deployer code is based on code saved to file from running the script SaveProxyDeployerConfig.s.sol
        DeterministicUUPSProxyDeployer uupsProxyDeployer = createOrGetUUPSProxyDeployer();

        vm.stopBroadcast();

        SparksDeterministicConfig memory config;

        config.manager = mineForProxyAddress(uupsProxyDeployer, deployer);
        config.sparks1155 = mineForSparks1155Address(config.manager.deployedAddress);

        config.deploymentCaller = deployer;
        writeSparksSparksDeterministicConfig(config, "sparksProxy");
    }
}
