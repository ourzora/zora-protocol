// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../src/deployment/CoinsDeployerBase.sol";

/// @title DeployLimitOrders
/// @notice Deploys limit order contracts in dev mode (non-deterministic)
/// @dev This script only works in dev mode (DEV=true environment variable).
///      For production deployments, use the TypeScript Turnkey script: deployLimitOrdersWithTurnkey.ts
///      This script deploys both ZoraLimitOrderBook and SwapWithLimitOrders with the proxy admin as owner.
contract DeployLimitOrders is CoinsDeployerBase {
    function run() public {
        bool isDev = isDevEnvironment();

        // Production deployments must use the TypeScript Turnkey script
        require(isDev, "Production deployments must use deployLimitOrdersWithTurnkey.ts script");

        console.log("\n=== Dev Mode: Non-deterministic deployment ===");

        // Read existing deployment
        CoinsDeployment memory deployment = readDeployment();

        require(deployment.zoraFactory != address(0), "ZORA_FACTORY not deployed");
        require(deployment.zoraHookRegistry != address(0), "ZORA_HOOK_REGISTRY not deployed");

        vm.startBroadcast();

        address owner = getProxyAdmin();
        address poolManager = getUniswapV4PoolManager();

        // 1. Deploy ZoraLimitOrderBook (non-deterministic)
        console.log("\n=== Deploying ZoraLimitOrderBook ===");
        address deployedLimitOrderBook = deployLimitOrderBook(poolManager, deployment.zoraFactory, deployment.zoraHookRegistry, owner, getWeth());
        console.log("Deployed ZORA_LIMIT_ORDER_BOOK:", deployedLimitOrderBook);
        console.log("Owner:", owner);

        // 2. Deploy SwapWithLimitOrders router (non-deterministic)
        console.log("\n=== Deploying SwapWithLimitOrders Router ===");
        address swapRouter = getUniswapSwapRouter();
        address deployedSwapRouter = deploySwapRouter(poolManager, deployedLimitOrderBook, swapRouter, PERMIT2, owner);
        console.log("Deployed ZORA_ROUTER:", deployedSwapRouter);
        console.log("Owner:", owner);

        vm.stopBroadcast();

        // Update and save deployment
        deployment.zoraLimitOrderBook = deployedLimitOrderBook;
        deployment.zoraRouter = deployedSwapRouter;
        saveDeployment(deployment);

        console.log("\n=== Dev Deployment Complete ===");
        console.log("Addresses saved to addresses/", vm.toString(block.chainid), "_dev.json");
        console.log("Owner permissions (Ownable2Step):");
        console.log("  - create() on LimitOrderBook: Public by default (owner can restrict via setPermittedCallers)");
        console.log("  - setMaxFillCount() on LimitOrderBook: Owner only");
        console.log("  - setLimitOrderConfig() on SwapRouter: Owner only");
        console.log("  - setPermittedCallers() on LimitOrderBook: Owner only");
    }
}
