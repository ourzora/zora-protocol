// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../src/deployment/CoinsDeployerBase.sol";

contract DeployHookRegistryScript is CoinsDeployerBase {
    function run() public {
        CoinsDeployment memory deployment = readDeployment();

        require(deployment.zoraHookRegistry != address(0), "ZORA_HOOK_REGISTRY not computed - run ComputeDeterministicAddresses first");

        address expectedHookRegistry = deployment.zoraHookRegistry;

        console.log("=== Deploying Hook Registry ===");
        console.log("Expected ZORA_HOOK_REGISTRY:", expectedHookRegistry);

        vm.startBroadcast();

        // Get proxy admin as initial owner
        address proxyAdmin = getProxyAdmin();
        address[] memory initialOwners = new address[](1);
        initialOwners[0] = proxyAdmin;

        address deployedHookRegistry = deployHookRegistryDeterministic(initialOwners);

        vm.stopBroadcast();

        console.log("Deployed ZORA_HOOK_REGISTRY:", deployedHookRegistry);

        require(deployedHookRegistry == expectedHookRegistry, "Hook registry address mismatch");

        console.log("\n=== Hook Registry Deployment Successful ===");
        console.log("Address matches expected:", deployedHookRegistry == expectedHookRegistry);

        deployment.zoraHookRegistry = deployedHookRegistry;
        saveDeployment(deployment);
    }
}
