// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import {ZoraDeployerBase} from "../src/deployment/ZoraDeployerBase.sol";
import {ChainConfig, Deployment} from "../src/deployment/DeploymentConfig.sol";
import {UUPSUpgradeable} from "@zoralabs/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {ZoraDeployerUtils} from "../src/deployment/ZoraDeployerUtils.sol";

contract UpgradePreminter is ZoraDeployerBase {
    function run() public returns (string memory, bytes memory upgradeCalldata, address upgradeTarget) {
        Deployment memory deployment = getDeployment();

        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        address preminterImplementation = ZoraDeployerUtils.deployNewPreminterImplementationDeterminstic(deployment.factoryProxy);

        vm.stopBroadcast();

        upgradeCalldata = abi.encodeWithSelector(UUPSUpgradeable.upgradeTo.selector, preminterImplementation);

        upgradeTarget = deployment.preminterImpl;

        console2.log("Upgrade PremintExecutor target and implementation:", upgradeTarget, preminterImplementation);
        console2.log("To upgrade, use this calldata:");
        console2.logBytes(upgradeCalldata);

        return (getDeploymentJSON(deployment), upgradeCalldata, upgradeTarget);
    }
}
