// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import {ZoraDeployerBase} from "./ZoraDeployerBase.sol";
import {ChainConfig, Deployment} from "../src/deployment/DeploymentConfig.sol";
import {UUPSUpgradeable} from "@zoralabs/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {ZoraDeployer} from "../src/deployment/ZoraDeployer.sol";

contract UpgradePreminter is ZoraDeployerBase {
    function run() public returns (string memory, bytes memory upgradeCalldata, address upgradeTarget) {
        Deployment memory deployment = getDeployment();

        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        address preminterImplementation = ZoraDeployer.deployNewPreminterImplementation(deployment.factoryProxy);

        vm.stopBroadcast();

        upgradeCalldata = abi.encodeWithSelector(UUPSUpgradeable.upgradeTo.selector, preminterImplementation);

        upgradeTarget = deployment.preminter;

        console2.log("Upgrade PremintExecutor target and implementatin:", upgradeTarget, preminterImplementation);
        console2.log("To upgrade, use this calldata:");
        console2.logBytes(upgradeCalldata);

        return (getDeploymentJSON(deployment), upgradeCalldata, upgradeTarget);
    }
}
