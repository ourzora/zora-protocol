// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../src/deployment/CoinsDeployerBase.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/// @title DeployAllContracts
/// @notice Atomically deploys all contracts in the correct order to avoid circular dependencies
/// @dev This script deploys everything in a single transaction batch:
///      1. Factory proxy (without implementation)
///      2. Hook registry
///      3. Order book authority
///      4. Limit order book
///      5. Swap router
///      6. Trusted message sender lookup
///      7. Upgrade gate
///      8. Factory implementations (including hook, which now has LOB address)
///      9. Upgrade factory proxy to implementation
contract DeployAllDevContracts is CoinsDeployerBase {
    function run() public {
        CoinsDeployment memory deployment = readDeployment();

        vm.startBroadcast();

        // Step 1: Deploy proxy shim and factory proxy (without implementation)
        console.log("\n=== Step 1: Deploying Factory Proxy ===");
        deployment = deployFactoryProxyOnly(deployment);
        console.log("PROXY_SHIM:", computeProxyShimAddress());
        console.log("ZORA_FACTORY proxy:", deployment.zoraFactory);

        // Step 2: Deploy hook registry (non-deterministic for dev deployments)
        console.log("\n=== Step 2: Deploying Hook Registry ===");
        address[] memory initialOwners = new address[](2);
        initialOwners[0] = getProxyAdmin();
        initialOwners[1] = deployment.zoraFactory;
        ZoraHookRegistry hookRegistry = new ZoraHookRegistry();
        hookRegistry.initialize(initialOwners);
        deployment.zoraHookRegistry = address(hookRegistry);
        console.log("ZORA_HOOK_REGISTRY:", deployment.zoraHookRegistry);

        // Step 3: Deploy order book authority (create() is set to PUBLIC_ROLE in constructor)
        console.log("\n=== Step 3: Deploying Order Book Authority ===");
        deployment.orderBookAuthority = deployOrderBookAuthorityDeterministic(getProxyAdmin());
        console.log("ORDER_BOOK_AUTHORITY:", deployment.orderBookAuthority);

        // Step 4: Deploy limit order book
        console.log("\n=== Step 4: Deploying Limit Order Book ===");
        deployment.zoraLimitOrderBook = deployLimitOrderBookDeterministic(
            getUniswapV4PoolManager(),
            deployment.zoraFactory,
            deployment.zoraHookRegistry,
            deployment.orderBookAuthority,
            getWeth()
        );
        console.log("ZORA_LIMIT_ORDER_BOOK:", deployment.zoraLimitOrderBook);

        // Step 5: Deploy swap router
        console.log("\n=== Step 5: Deploying Swap Router ===");
        deployment.zoraRouter = deploySwapRouterDeterministic(getUniswapV4PoolManager(), deployment.zoraLimitOrderBook, getUniswapSwapRouter(), PERMIT2);
        console.log("ZORA_ROUTER:", deployment.zoraRouter);

        // Step 6: Deploy trusted message sender lookup
        console.log("\n=== Step 6: Deploying Trusted Message Sender Lookup ===");
        deployment.trustedMsgSenderLookup = address(
            new TrustedMsgSenderProviderLookup(getDefaultTrustedMessageSenders(deployment.zoraRouter), getProxyAdmin())
        );
        console.log("TRUSTED_MSG_SENDER_LOOKUP:", deployment.trustedMsgSenderLookup);

        // Step 7: Deploy upgrade gate
        console.log("\n=== Step 7: Deploying Upgrade Gate ===");
        deployment.hookUpgradeGate = address(new HookUpgradeGate(getProxyAdmin()));
        console.log("HOOK_UPGRADE_GATE:", deployment.hookUpgradeGate);

        // Step 8: Deploy coin implementations
        console.log("\n=== Step 8: Deploying Coin Implementations ===");
        deployment.coinV4Impl = address(deployCoinV4Impl());
        deployment.creatorCoinImpl = address(deployCreatorCoinImpl());
        console.log("COIN_V4_IMPL:", deployment.coinV4Impl);
        console.log("CREATOR_COIN_IMPL:", deployment.creatorCoinImpl);

        // Step 9: Deploy hook (needs all dependencies including LOB)
        console.log("\n=== Step 9: Deploying Content Coin Hook ===");
        (IHooks zoraV4CoinHook, bytes32 usedSalt) = deployZoraV4CoinHook(deployment);
        deployment.zoraV4CoinHook = address(zoraV4CoinHook);
        deployment.zoraV4CoinHookSalt = usedSalt;
        console.log("ZORA_V4_COIN_HOOK:", deployment.zoraV4CoinHook);

        // Step 10: Deploy factory implementation
        console.log("\n=== Step 10: Deploying Factory Implementation ===");
        deployment.zoraFactoryImpl = deployFactoryImpl(deployment);
        deployment.coinVersion = IVersionedContract(deployment.coinV4Impl).contractVersion();
        console.log("ZORA_FACTORY_IMPL:", deployment.zoraFactoryImpl);
        console.log("COIN_VERSION:", deployment.coinVersion);

        // Step 11: Upgrade factory proxy to implementation
        console.log("\n=== Step 11: Upgrading Factory Proxy ===");
        UUPSUpgradeable(deployment.zoraFactory).upgradeToAndCall(deployment.zoraFactoryImpl, "");
        ZoraFactoryImpl(deployment.zoraFactory).initialize(getProxyAdmin());
        console.log("Factory upgraded and initialized");

        vm.stopBroadcast();

        // Save deployment addresses
        saveDeployment(deployment);

        console.log("\n=== Deployment Complete ===");
        console.log("All contracts deployed successfully!");
        console.log("Deployment saved to:", addressesFile());
    }

    /// @notice Deploys only the factory proxy without the implementation
    /// @dev This allows the factory address to be known before deploying the hook
    function deployFactoryProxyOnly(CoinsDeployment memory deployment) internal returns (CoinsDeployment memory) {
        require(getProxyAdmin() != address(0), "Owner cannot be zero address");

        // Deploy ProxyShim (using CREATE, not CREATE2)
        ProxyShim proxyShim = new ProxyShim();

        // Deploy ZoraFactory proxy (using CREATE, not CREATE2)
        ZoraFactory factoryProxy = new ZoraFactory(address(proxyShim));

        deployment.zoraFactory = address(factoryProxy);

        return deployment;
    }
}
