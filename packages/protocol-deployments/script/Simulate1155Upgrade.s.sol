// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import {ZoraDeployerBase} from "../src/ZoraDeployerBase.sol";
import {ZoraDeployerUtils} from "../src/ZoraDeployerUtils.sol";
import {Deployment, ChainConfig} from "../src/DeploymentConfig.sol";
import {DeterministicDeployerScript} from "../src/DeterministicDeployerScript.sol";

/// @dev Deploys implementation contracts for 1155 contracts.
/// @notice Run after deploying the minters
/// @notice This
contract Simulate1155Upgrade is ZoraDeployerBase {
    function run() public returns (string memory) {
        Deployment memory deployment = getDeployment();

        ChainConfig memory chainConfig = getChainConfig();

        address creator = makeAddr("creator");

        vm.startBroadcast(chainConfig.factoryOwner);

        (address target, bytes memory upgradeCalldata) = ZoraDeployerUtils.simulateUpgrade(deployment);

        console2.log("upgrade 1155 target:", target);
        console2.log("calldata:");
        console.logBytes(upgradeCalldata);

        ZoraDeployerUtils.deployTestContractForVerification(deployment.factoryProxy, creator);

        vm.stopBroadcast();

        return getDeploymentJSON(deployment);
    }
}
