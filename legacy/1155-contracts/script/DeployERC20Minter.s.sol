// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import {ZoraDeployerBase} from "../src/deployment/ZoraDeployerBase.sol";
import {ZoraDeployerUtils} from "../src/deployment/ZoraDeployerUtils.sol";
import {Deployment, ChainConfig} from "../src/deployment/DeploymentConfig.sol";

contract DeployErc20Minter is ZoraDeployerBase {
    function run() public returns (string memory) {
        Deployment memory deployment = getDeployment();
        ChainConfig memory chainConfig = getChainConfig();

        vm.startBroadcast();

        deployment.erc20Minter = ZoraDeployerUtils.deployErc20Minter(chainConfig);

        vm.stopBroadcast();

        return getDeploymentJSON(deployment);
    }
}
