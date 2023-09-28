// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import {ZoraDeployerBase} from "./ZoraDeployerBase.sol";
import {ChainConfig, Deployment} from "../src/deployment/DeploymentConfig.sol";
import {ZoraDeployerUtils} from "../src/deployment/ZoraDeployerUtils.sol";
import {DeterministicProxyDeployer} from "../src/deployment/DeterministicProxyDeployer.sol";
import {DeterministicDeployerScript, DeterministicParams} from "../src/deployment/DeterministicDeployerScript.sol";

contract DeployNewProxies is ZoraDeployerBase, DeterministicDeployerScript {
    using stdJson for string;

    function run() public returns (string memory) {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        // address deployer = vm.envAddress("DEPLOYER");

        uint256 chain = chainId();

        ChainConfig memory chainConfig = getChainConfig();
        Deployment memory deployment = getDeployment();

        // get signing instructions
        vm.startBroadcast(deployerPrivateKey);

        // Sanity check to make sure that the factory owner is a smart contract.
        // This may catch cross-chain data copy mistakes where there is no safe at the desired admin address.
        if (
            address(chainConfig.factoryOwner).code.length == 0
        ) {
            revert("FactoryOwner should be a contract. See DeployNewProxies:31.");
        }

        address factoryProxyAddress = deployDeterministicProxy({
            proxyName: "factoryProxy",
            implementation: deployment.factoryImpl,
            owner: chainConfig.factoryOwner,
            chain: chain
        });

        address preminterProxyAddress = deployDeterministicProxy({
            proxyName: "premintExecutorProxy",
            implementation: deployment.preminterImpl,
            owner: chainConfig.factoryOwner,
            chain: chain
        });

        address upgradeGateAddress = deployUpgradeGate({
            chain: chain,
            upgradeGateOwner: chainConfig.factoryOwner
        });

        vm.stopBroadcast();

        deployment.factoryProxy = factoryProxyAddress;
        deployment.preminterProxy = preminterProxyAddress;
        deployment.upgradeGate = upgradeGateAddress;

        return getDeploymentJSON(deployment);
    }
}
