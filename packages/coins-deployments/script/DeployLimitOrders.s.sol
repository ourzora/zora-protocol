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
contract DeployLimitOrders is CoinsDeployerBase {
    function run() public {
        // Read existing deployment with expected addresses
        CoinsDeployment memory deployment = readDeployment();

        require(deployment.zoraFactory != address(0), "ZORA_FACTORY not deployed");
        require(deployment.zoraHookRegistry != address(0), "ZORA_HOOK_REGISTRY not deployed");
        require(deployment.zoraLimitOrderBook != address(0), "ZORA_LIMIT_ORDER_BOOK not computed - run ComputeDeterministicAddresses first");
        require(deployment.zoraRouter != address(0), "ZORA_ROUTER not computed - run ComputeDeterministicAddresses first");

        address expectedLimitOrderBook = deployment.zoraLimitOrderBook;
        address expectedSwapRouter = deployment.zoraRouter;

        console.log("\n=== Expected Addresses ===");
        console.log("ZORA_LIMIT_ORDER_BOOK:", expectedLimitOrderBook);
        console.log("ZORA_ROUTER:", expectedSwapRouter);

        vm.startBroadcast();

        address owner = getProxyAdmin();
        address poolManager = getUniswapV4PoolManager();

        // 1. Deploy ZoraLimitOrderBook deterministically
        console.log("\n=== Deploying ZoraLimitOrderBook ===");
        address deployedLimitOrderBook = deployLimitOrderBookDeterministic(
            poolManager,
            deployment.zoraFactory,
            deployment.zoraHookRegistry,
            owner,
            getWeth()
        );
        require(deployedLimitOrderBook == expectedLimitOrderBook, "Limit order book address mismatch");
        console.log("Deployed ZORA_LIMIT_ORDER_BOOK:", deployedLimitOrderBook);
        console.log("Owner:", owner);
        console.log("Address verified: MATCH");

        // 2. Deploy SwapWithLimitOrders router deterministically
        console.log("\n=== Deploying SwapWithLimitOrders Router ===");
        address swapRouter = getUniswapSwapRouter();
        address deployedSwapRouter = deploySwapRouterDeterministic(poolManager, deployedLimitOrderBook, swapRouter, PERMIT2, owner);
        require(deployedSwapRouter == expectedSwapRouter, "Swap router address mismatch");
        console.log("Deployed ZORA_ROUTER:", deployedSwapRouter);
        console.log("Owner:", owner);
        console.log("Address verified: MATCH");

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
