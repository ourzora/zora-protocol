// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import {ZoraDeployerBase} from "../src/ZoraDeployerBase.sol";
import {ZoraDeployerUtils} from "../src/ZoraDeployerUtils.sol";
import {Deployment} from "../src/DeploymentConfig.sol";

contract DeployMintersAndImplementations is ZoraDeployerBase {
    function run() public returns (string memory) {
        Deployment memory deployment = getDeployment();

        vm.startBroadcast();

        deployMinters(deployment);

        deployNew1155AndFactoryImpl(deployment);

        deployNewPreminterImplementationDeterminstic(deployment);

        vm.stopBroadcast();

        return getDeploymentJSON(deployment);
    }
}
