// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import {ZoraDeployerBase} from "./ZoraDeployerBase.sol";
import {ChainConfig, Deployment} from "../src/deployment/DeploymentConfig.sol";

contract DeployNewPreminterAndFactoryProxy is ZoraDeployerBase {
    function run() public returns (string memory) {
        Deployment memory deployment = getDeployment();

        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        // address deployer = vm.envAddress("DEPLOYER");

        vm.startBroadcast(deployerPrivateKey);

        // deployNew1155AndFactoryProxy(deployment, deployer);

        deployNewPreminterProxy(deployment);

        vm.stopBroadcast();

        return getDeploymentJSON(deployment);
    }
}
