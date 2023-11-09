// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import {ZoraDeployerBase} from "../src/ZoraDeployerBase.sol";
import {Deployment} from "../src/DeploymentConfig.sol";
import {ZoraDeployerUtils} from "../src/ZoraDeployerUtils.sol";
import {DeploymentTestingUtils} from "../src/DeploymentTestingUtils.sol";

contract DeployProxiesToNewChain is ZoraDeployerBase, DeploymentTestingUtils {
    function run() public returns (string memory) {
        Deployment memory deployment = getDeployment();

        vm.startBroadcast();

        console.log("deploy factory proxy");

        deployFactoryProxyDeterminstic(deployment);

        console2.log("factory proxy address:", deployment.factoryProxy);

        console2.log("create test contract for verification");

        ZoraDeployerUtils.deployTestContractForVerification(deployment.factoryProxy, makeAddr("admin"));

        deployPreminterProxyDeterminstic(deployment);

        console2.log("preminter proxy", deployment.preminterProxy);

        console2.log("testing premint");

        signAndExecutePremint(deployment.preminterProxy);

        vm.stopBroadcast();

        // now test signing and executing premint

        return getDeploymentJSON(deployment);
    }
}
