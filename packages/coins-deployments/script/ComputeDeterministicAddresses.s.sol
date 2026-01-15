// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../src/deployment/CoinsDeployerBase.sol";

/// @title ComputeDeterministicAddresses
/// @notice Computes and saves deterministic addresses for factory and limit order contracts
/// @dev Step 1 of the two-step deployment process. Run this first to compute expected addresses,
///      then use DeployFactoryNonDeterministic.s.sol and/or DeployLimitOrders.s.sol to deploy and verify addresses match.
contract ComputeDeterministicAddresses is CoinsDeployerBase {
    function run() public {
        // Read existing deployment to get dependencies
        CoinsDeployment memory deployment = readDeployment();

        // If factory is not deployed and we're in DEV mode, compute its deterministic address
        if (deployment.zoraFactory == address(0) && isDevEnvironment()) {
            console.log("\n=== Computing Factory Address (DEV mode) ===");
            address computedProxyShim = computeProxyShimAddress();
            console.log("Computed PROXY_SHIM:", computedProxyShim);

            address computedFactory = computeFactoryAddress(computedProxyShim);
            console.log("Computed ZORA_FACTORY:", computedFactory);

            deployment.zoraFactory = computedFactory;
        } else if (deployment.zoraFactory == address(0)) {
            revert("ZORA_FACTORY not deployed. In production, run Deploy.s.sol first.");
        } else {
            console.log("\n=== Factory Already Deployed ===");
            console.log("ZORA_FACTORY:", deployment.zoraFactory);
        }

        // If hook registry is not deployed and we're in DEV mode, compute its deterministic address
        if (deployment.zoraHookRegistry == address(0) && isDevEnvironment()) {
            console.log("\n=== Computing Hook Registry Address (DEV mode) ===");
            address computedHookRegistry = computeHookRegistryAddress();
            console.log("Computed ZORA_HOOK_REGISTRY:", computedHookRegistry);

            deployment.zoraHookRegistry = computedHookRegistry;
        } else if (deployment.zoraHookRegistry == address(0)) {
            revert("ZORA_HOOK_REGISTRY not deployed. In production, run Deploy.s.sol first.");
        } else {
            console.log("\n=== Hook Registry Already Deployed ===");
            console.log("ZORA_HOOK_REGISTRY:", deployment.zoraHookRegistry);
        }

        // Compute deterministic addresses using hardcoded salts
        address proxyAdmin = getProxyAdmin();
        address poolManager = getUniswapV4PoolManager();
        address swapRouter = getUniswapSwapRouter();

        console.log("\n=== Computing Limit Order Addresses ===");

        // 1. Compute authority address (no circular dependency - single-contract authority)
        address computedAuthority = computeAuthorityAddress(proxyAdmin);
        console.log("Computed ORDER_BOOK_AUTHORITY:", computedAuthority);

        // 2. Compute limit order book address
        address computedLimitOrderBook = computeLimitOrderBookAddress(
            poolManager,
            deployment.zoraFactory,
            deployment.zoraHookRegistry,
            computedAuthority,
            getWeth()
        );
        console.log("Computed ZORA_LIMIT_ORDER_BOOK:", computedLimitOrderBook);

        // 3. Compute swap router address
        address computedSwapRouter = computeSwapRouterAddress(poolManager, computedLimitOrderBook, swapRouter, PERMIT2);
        console.log("Computed ZORA_ROUTER:", computedSwapRouter);

        // Save computed addresses to deployment
        deployment.orderBookAuthority = computedAuthority;
        deployment.zoraLimitOrderBook = computedLimitOrderBook;
        deployment.zoraRouter = computedSwapRouter;

        saveDeployment(deployment);

        console.log("\n=== Computed Deterministic Addresses Saved ===");
        console.log("ZORA_FACTORY:", deployment.zoraFactory);
        console.log("ZORA_HOOK_REGISTRY:", deployment.zoraHookRegistry);
        console.log("ORDER_BOOK_AUTHORITY:", deployment.orderBookAuthority);
        console.log("ZORA_LIMIT_ORDER_BOOK:", deployment.zoraLimitOrderBook);
        console.log("ZORA_ROUTER:", deployment.zoraRouter);
        console.log("\nNext steps:");
        console.log("1. If factory not deployed: Run DeployFactoryNonDeterministic.s.sol");
        console.log("2. If hook registry not deployed: Run DeployHookRegistry.s.sol");
        console.log("3. Run DeployTrustedMsgSenderLookup.s.sol");
        console.log("4. Run DeployLimitOrders.s.sol");
    }
}
