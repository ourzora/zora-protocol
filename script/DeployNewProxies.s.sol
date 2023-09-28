// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import {ZoraDeployerBase} from "./ZoraDeployerBase.sol";
import {ChainConfig, Deployment} from "../src/deployment/DeploymentConfig.sol";
import {ZoraDeployerUtils} from "../src/deployment/ZoraDeployerUtils.sol";
import {NewFactoryProxyDeployer} from "../src/deployment/NewFactoryProxyDeployer.sol";
import {DeterminsticDeployerScript, DeterminsticParams} from "../src/deployment/DeterminsticDeployerScript.sol";

contract DeployNewProxies is ZoraDeployerBase, DeterminsticDeployerScript {
    using stdJson for string;

    function run() public returns (string memory) {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        // address deployer = vm.envAddress("DEPLOYER");

        uint256 chain = chainId();

        ChainConfig memory chainConfig = getChainConfig();
        Deployment memory deployment = getDeployment();

        // get signing instructions
        vm.startBroadcast(deployerPrivateKey);

        address factoryProxyAddress = deployDeterminsticProxy({
            proxyName: "factoryProxy",
            implementation: deployment.factoryImpl,
            owner: chainConfig.factoryOwner,
            chain: chain
        });

        address preminterProxyAddress = deployDeterminsticProxy({
            proxyName: "premintExecutorProxy",
            implementation: deployment.preminterImpl,
            owner: chainConfig.factoryOwner,
            chain: chain
        });

        vm.stopBroadcast();

        deployment.factoryProxy = factoryProxyAddress;
        deployment.preminterProxy = preminterProxyAddress;

        return getDeploymentJSON(deployment);
    }
}
