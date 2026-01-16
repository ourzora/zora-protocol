// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../src/deployment/CoinsDeployerBase.sol";

/// @title DeployLimitOrders
/// @notice Deploys limit order contracts using CREATE2 and verifies addresses match expected values
/// @dev Step 2 of the two-step deployment process. Run ComputeDeterministicAddresses.s.sol first.
///      This script:
///      1. Reads expected addresses from JSON
///      2. Deploys contracts deterministically
///      3. Verifies deployed addresses match expected
///      Both contracts use Ownable2Step with the multisig as owner.
///      Note: Swap router should already be registered in TrustedMsgSenderProviderLookup during its deployment
///      In dev mode (DEV=true), contracts are deployed non-deterministically without address verification.
contract DeployLimitOrders is CoinsDeployerBase {
    function run() public {
        // Read existing deployment with expected addresses
        CoinsDeployment memory deployment = readDeployment();

        require(deployment.zoraFactory != address(0), "ZORA_FACTORY not deployed");
        require(deployment.zoraHookRegistry != address(0), "ZORA_HOOK_REGISTRY not deployed");

        bool isDev = isDevEnvironment();

        // In production, require pre-computed addresses
        if (!isDev) {
            require(deployment.zoraLimitOrderBook != address(0), "ZORA_LIMIT_ORDER_BOOK not computed - run ComputeDeterministicAddresses first");
            require(deployment.zoraRouter != address(0), "ZORA_ROUTER not computed - run ComputeDeterministicAddresses first");

            console.log("\n=== Expected Addresses ===");
            console.log("ZORA_LIMIT_ORDER_BOOK:", deployment.zoraLimitOrderBook);
            console.log("ZORA_ROUTER:", deployment.zoraRouter);
        } else {
            console.log("\n=== Dev Mode: Non-deterministic deployment ===");
        }

        vm.startBroadcast();

        address owner = getProxyAdmin();
        address poolManager = getUniswapV4PoolManager();
        address deployedLimitOrderBook;
        address deployedSwapRouter;

        // 1. Deploy ZoraLimitOrderBook
        console.log("\n=== Deploying ZoraLimitOrderBook ===");
        if (isDev) {
            deployedLimitOrderBook = deployLimitOrderBook(poolManager, deployment.zoraFactory, deployment.zoraHookRegistry, owner, getWeth());
        } else {
            deployedLimitOrderBook = deployLimitOrderBookDeterministic(poolManager, deployment.zoraFactory, deployment.zoraHookRegistry, owner, getWeth());
            require(deployedLimitOrderBook == deployment.zoraLimitOrderBook, "Limit order book address mismatch");
            console.log("Address verified: MATCH");
        }
        console.log("Deployed ZORA_LIMIT_ORDER_BOOK:", deployedLimitOrderBook);
        console.log("Owner:", owner);

        // 2. Deploy SwapWithLimitOrders router
        console.log("\n=== Deploying SwapWithLimitOrders Router ===");
        address swapRouter = getUniswapSwapRouter();
        if (isDev) {
            deployedSwapRouter = deploySwapRouter(poolManager, deployedLimitOrderBook, swapRouter, PERMIT2, owner);
        } else {
            deployedSwapRouter = deploySwapRouterDeterministic(poolManager, deployedLimitOrderBook, swapRouter, PERMIT2, owner);
            require(deployedSwapRouter == deployment.zoraRouter, "Swap router address mismatch");
            console.log("Address verified: MATCH");
        }
        console.log("Deployed ZORA_ROUTER:", deployedSwapRouter);
        console.log("Owner:", owner);

        vm.stopBroadcast();

        // Update and save deployment
        deployment.zoraLimitOrderBook = deployedLimitOrderBook;
        deployment.zoraRouter = deployedSwapRouter;
        saveDeployment(deployment);

        console.log("\n=== Deployment Complete ===");
        console.log("All addresses verified and saved successfully");
        console.log("Owner permissions (Ownable2Step):");
        console.log("  - create() on LimitOrderBook: Public by default (owner can restrict via setPermittedCallers)");
        console.log("  - setMaxFillCount() on LimitOrderBook: Owner only");
        console.log("  - setLimitOrderConfig() on SwapRouter: Owner only");
        console.log("  - setPermittedCallers() on LimitOrderBook: Owner only");
    }
}
