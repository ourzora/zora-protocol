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
///      Access permissions (create = PUBLIC) are configured in the authority constructor.
///      Note: Swap router should already be registered in TrustedMsgSenderProviderLookup during its deployment
contract DeployLimitOrders is CoinsDeployerBase {
    function run() public {
        // Read existing deployment with expected addresses
        CoinsDeployment memory deployment = readDeployment();

        require(deployment.zoraFactory != address(0), "ZORA_FACTORY not deployed");
        require(deployment.zoraHookRegistry != address(0), "ZORA_HOOK_REGISTRY not deployed");
        require(deployment.orderBookAuthority != address(0), "ORDER_BOOK_AUTHORITY not computed - run ComputeDeterministicAddresses first");
        require(deployment.zoraLimitOrderBook != address(0), "ZORA_LIMIT_ORDER_BOOK not computed - run ComputeDeterministicAddresses first");
        require(deployment.zoraRouter != address(0), "ZORA_ROUTER not computed - run ComputeDeterministicAddresses first");

        address expectedAuthority = deployment.orderBookAuthority;
        address expectedLimitOrderBook = deployment.zoraLimitOrderBook;
        address expectedSwapRouter = deployment.zoraRouter;

        console.log("\n=== Expected Addresses ===");
        console.log("ORDER_BOOK_AUTHORITY:", expectedAuthority);
        console.log("ZORA_LIMIT_ORDER_BOOK:", expectedLimitOrderBook);
        console.log("ZORA_ROUTER:", expectedSwapRouter);

        vm.startBroadcast();

        // 1. Deploy OrderBookAuthority deterministically
        // Admin is proxyAdmin (multisig), initial function roles set create() to PUBLIC_ROLE
        console.log("\n=== Deploying OrderBookAuthority ===");
        address proxyAdmin = getProxyAdmin();
        address poolManager = getUniswapV4PoolManager();

        address deployedAuthority = deployOrderBookAuthorityDeterministic(proxyAdmin);
        require(deployedAuthority == expectedAuthority, "Authority address mismatch");
        console.log("Deployed ORDER_BOOK_AUTHORITY:", deployedAuthority);
        console.log("Admin:", proxyAdmin);
        console.log("Address verified: MATCH");

        // 2. Deploy ZoraLimitOrderBook deterministically
        console.log("\n=== Deploying ZoraLimitOrderBook ===");
        address deployedLimitOrderBook = deployLimitOrderBookDeterministic(poolManager, deployment.zoraFactory, deployment.zoraHookRegistry, deployedAuthority);
        require(deployedLimitOrderBook == expectedLimitOrderBook, "Limit order book address mismatch");
        console.log("Deployed ZORA_LIMIT_ORDER_BOOK:", deployedLimitOrderBook);
        console.log("Address verified: MATCH");

        // 3. Deploy SwapWithLimitOrders router deterministically
        console.log("\n=== Deploying SwapWithLimitOrders Router ===");
        address swapRouter = getUniswapSwapRouter();
        address deployedSwapRouter = deploySwapRouterDeterministic(poolManager, deployedLimitOrderBook, swapRouter, PERMIT2);
        require(deployedSwapRouter == expectedSwapRouter, "Swap router address mismatch");
        console.log("Deployed ZORA_ROUTER:", deployedSwapRouter);
        console.log("Address verified: MATCH");

        vm.stopBroadcast();

        // Update and save deployment
        deployment.orderBookAuthority = deployedAuthority;
        deployment.zoraLimitOrderBook = deployedLimitOrderBook;
        deployment.zoraRouter = deployedSwapRouter;
        saveDeployment(deployment);

        console.log("\n=== Deployment Complete ===");
        console.log("All addresses verified and saved successfully");
        console.log("Access permissions configured in constructor:");
        console.log("  - create() on LimitOrderBook: PUBLIC_ROLE (anyone can call)");
        console.log("  - setMaxFillCount() on LimitOrderBook: ADMIN_ROLE (multisig only)");
    }
}
