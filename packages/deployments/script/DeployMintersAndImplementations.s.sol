// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import {ZoraDeployerBase} from "@zoralabs/zora-1155-contracts/src/deployment/ZoraDeployerBase.sol";
import {ZoraDeployerUtils} from "@zoralabs/zora-1155-contracts/src/deployment/ZoraDeployerUtils.sol";
import {Deployment} from "@zoralabs/zora-1155-contracts/src/deployment/DeploymentConfig.sol";

contract DeployMintersAndImplementations is ZoraDeployerBase {
    function run() public returns (string memory) {
        Deployment memory deployment = getDeployment();

        address deployer = vm.envAddress("DEPLOYER");

        vm.startBroadcast(deployer);

        deployUpgradeGateDeterminstic(deployment);

        deployMinters(deployment);

        deployNew1155AndFactoryImpl(deployment);

        deployNewPreminterImplementationDeterminstic(deployment);

        vm.stopBroadcast();

        return getDeploymentJSON(deployment);
    }
}
