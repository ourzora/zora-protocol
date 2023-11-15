// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import {ZoraCreator1155FactoryImpl} from "@zoralabs/zora-1155-contracts/src/factory/ZoraCreator1155FactoryImpl.sol";
import {ForkDeploymentConfig, Deployment, ChainConfig} from "../src/DeploymentConfig.sol";
import {ZoraDeployerUtils} from "../src/ZoraDeployerUtils.sol";

contract UpgradesTest is ForkDeploymentConfig, Test {
    /// @notice gets the chains to do fork tests on, by reading environment var FORK_TEST_CHAINS.
    /// Chains are by name, and must match whats under `rpc_endpoints` in the foundry.toml
    function getForkTestChains() private view returns (string[] memory result) {
        try vm.envString("FORK_TEST_CHAINS", ",") returns (string[] memory forkTestChains) {
            result = forkTestChains;
        } catch {
            console.log("could not get fork test chains - make sure the environment variable FORK_TEST_CHAINS is set");
            result = new string[](0);
        }
    }

    /// @notice checks which chains need an upgrade, simulated the upgrade, and gets the upgrade calldata
    function simulate1155UpgradeOnFork(string memory chainName) private {
        // create and select the fork, which will be used for all subsequent calls
        vm.createSelectFork(vm.rpcUrl(chainName));

        Deployment memory deployment = getDeployment();

        ChainConfig memory chainConfig = getChainConfig();

        address creator = makeAddr("creator");

        vm.startPrank(chainConfig.factoryOwner);

        address currentImplementation = ZoraCreator1155FactoryImpl(deployment.factoryProxy).implementation();

        if (currentImplementation != deployment.factoryImpl) {
            address targetImpl = deployment.factoryImpl;
            (address target, bytes memory upgradeCalldata) = ZoraDeployerUtils.simulateUpgrade(deployment);

            ZoraDeployerUtils.deployTestContractForVerification(deployment.factoryProxy, creator);

            console2.log("=== 1155 upgrade needed ===");
            console2.log("chain:", chainName);
            console2.log("upgrade owner:", chainConfig.factoryOwner);
            console2.log("upgrade target:", target);
            console2.log("upgrade calldata:");
            console.logBytes(upgradeCalldata);
            console2.log("upgrade to address:", targetImpl);
            console2.log("upgrade to version:", ZoraCreator1155FactoryImpl(targetImpl).contractVersion());
            console2.log("=====================\n");
        }
    }

    function test_fork_simulateUpgrades() external {
        string[] memory forkTestChains = getForkTestChains();
        for (uint256 i = 0; i < forkTestChains.length; i++) {
            simulate1155UpgradeOnFork(forkTestChains[i]);
        }
    }
}
