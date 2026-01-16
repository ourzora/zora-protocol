// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";

import {ProxyDeployerScript, DeterministicContractConfig, DeterministicDeployerAndCaller} from "@zoralabs/shared-contracts/deployment/ProxyDeployerScript.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ZoraFactoryImpl} from "@zoralabs/coins/src/ZoraFactoryImpl.sol";
import {IVersionedContract} from "@zoralabs/shared-contracts/interfaces/IVersionedContract.sol";
// import {BuySupplyWithSwapRouterHook} from "@zoralabs/coins/src/hooks/deployment/BuySupplyWithSwapRouterHook.sol";
import {IZoraFactory} from "@zoralabs/coins/src/interfaces/IZoraFactory.sol";
import {ContentCoin} from "@zoralabs/coins/src/ContentCoin.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {ZoraFactory} from "@zoralabs/coins/src/proxy/ZoraFactory.sol";
import {HooksDeployment} from "@zoralabs/coins/src/libs/HooksDeployment.sol";
import {ProxyShim} from "@zoralabs/coins/src/utils/ProxyShim.sol";
import {CreatorCoin} from "@zoralabs/coins/src/CreatorCoin.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {HookUpgradeGate} from "@zoralabs/coins/src/hooks/HookUpgradeGate.sol";
import {BuySupplyWithV4SwapHook} from "@zoralabs/coins/src/hooks/deployment/BuySupplyWithV4SwapHook.sol";
import {TrustedMsgSenderProviderLookup} from "@zoralabs/coins/src/utils/TrustedMsgSenderProviderLookup.sol";
import {ITrustedMsgSenderProviderLookup} from "@zoralabs/coins/src/interfaces/ITrustedMsgSenderProviderLookup.sol";
import {ZoraHookRegistry} from "@zoralabs/coins/src/hook-registry/ZoraHookRegistry.sol";
// Limit Orders imports
import {ZoraLimitOrderBook} from "@zoralabs/limit-orders/ZoraLimitOrderBook.sol";
import {IZoraLimitOrderBook} from "@zoralabs/limit-orders/IZoraLimitOrderBook.sol";
import {SwapWithLimitOrders} from "@zoralabs/limit-orders/router/SwapWithLimitOrders.sol";
import {ISetLimitOrderConfig} from "@zoralabs/limit-orders/router/ISetLimitOrderConfig.sol";
import {ISwapRouter} from "@zoralabs/coins/src/interfaces/ISwapRouter.sol";
import {ImmutableCreate2FactoryUtils} from "@zoralabs/shared-contracts/utils/ImmutableCreate2FactoryUtils.sol";

contract CoinsDeployerBase is ProxyDeployerScript {
    address internal constant PROTOCOL_REWARDS = 0x7777777F279eba3d3Ad8F4E708545291A6fDBA8B;
    address internal constant ZORA = 0x1111111111166b7FE7bd91427724B487980aFc69;
    address internal constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    // Hardcoded salts for deterministic deployment
    // First 20 bytes are 0 to allow any address to deploy
    bytes32 constant PROXY_SHIM_SALT = 0x0000000000000000000000000000000000000000000000000000000000000000;
    bytes32 constant LIMIT_ORDER_BOOK_SALT = 0x0000000000000000000000000000000000000000000000000000000000000002;
    bytes32 constant SWAP_ROUTER_SALT = 0x0000000000000000000000000000000000000000000000000000000000000003;
    bytes32 constant FACTORY_SALT = 0x0000000000000000000000000000000000000000000000000000000000000004;
    bytes32 constant HOOK_REGISTRY_SALT = 0x0000000000000000000000000000000000000000000000000000000000000005;

    using stdJson for string;

    struct CoinsDeployment {
        // Factory
        address zoraFactory;
        address zoraFactoryImpl;
        // Implementation
        address coinV3Impl;
        address coinV4Impl;
        address creatorCoinImpl;
        string coinVersion;
        // hooks
        address buySupplyWithSwapRouterHook;
        address zoraV4CoinHook;
        address hookUpgradeGate;
        // trusted sender lookup
        address trustedMsgSenderLookup;
        // Hook deployment salt (for deterministic deployment)
        bytes32 zoraV4CoinHookSalt;
        // Hook registry
        address zoraHookRegistry;
        // Limit order book
        address zoraLimitOrderBook;
        address zoraRouter;
    }

    function addressesFile() internal view returns (string memory) {
        if (isDevEnvironment()) {
            return string.concat("./addresses/", vm.toString(block.chainid), "_dev.json");
        }
        return string.concat("./addresses/", vm.toString(block.chainid), ".json");
    }

    function chainConfigPath() internal view override returns (string memory) {
        if (isDevEnvironment()) {
            return string.concat("./node_modules/@zoralabs/shared-contracts/chainConfigs/", vm.toString(block.chainid), "_dev.json");
        }
        return string.concat("./node_modules/@zoralabs/shared-contracts/chainConfigs/", vm.toString(block.chainid), ".json");
    }

    function saveDeployment(CoinsDeployment memory deployment) internal {
        string memory objectKey = "config";

        vm.serializeAddress(objectKey, "ZORA_FACTORY", deployment.zoraFactory);
        vm.serializeAddress(objectKey, "ZORA_FACTORY_IMPL", deployment.zoraFactoryImpl);
        vm.serializeString(objectKey, "COIN_VERSION", deployment.coinVersion);
        vm.serializeAddress(objectKey, "BUY_SUPPLY_WITH_SWAP_ROUTER_HOOK", deployment.buySupplyWithSwapRouterHook);
        vm.serializeAddress(objectKey, "COIN_V3_IMPL", deployment.coinV3Impl);
        vm.serializeAddress(objectKey, "ZORA_V4_COIN_HOOK", deployment.zoraV4CoinHook);
        vm.serializeBytes32(objectKey, "ZORA_V4_COIN_HOOK_SALT", deployment.zoraV4CoinHookSalt);
        vm.serializeAddress(objectKey, "CREATOR_COIN_IMPL", deployment.creatorCoinImpl);
        vm.serializeAddress(objectKey, "HOOK_UPGRADE_GATE", deployment.hookUpgradeGate);
        vm.serializeAddress(objectKey, "ZORA_HOOK_REGISTRY", deployment.zoraHookRegistry);
        vm.serializeAddress(objectKey, "TRUSTED_MSG_SENDER_LOOKUP", deployment.trustedMsgSenderLookup);
        vm.serializeAddress(objectKey, "ZORA_LIMIT_ORDER_BOOK", deployment.zoraLimitOrderBook);
        string memory result = vm.serializeAddress(objectKey, "ZORA_ROUTER", deployment.zoraRouter);
        vm.serializeAddress(objectKey, "COIN_V4_IMPL", deployment.coinV4Impl);

        vm.writeJson(result, addressesFile());
    }

    function readDeployment() internal returns (CoinsDeployment memory deployment) {
        string memory file = addressesFile();
        if (!vm.exists(file)) {
            return deployment;
        }
        string memory json = vm.readFile(file);

        deployment.zoraFactory = readAddressOrDefaultToZero(json, "ZORA_FACTORY");
        deployment.zoraFactoryImpl = readAddressOrDefaultToZero(json, "ZORA_FACTORY_IMPL");
        deployment.coinV3Impl = readAddressOrDefaultToZero(json, "COIN_V3_IMPL");
        deployment.coinV4Impl = readAddressOrDefaultToZero(json, "COIN_V4_IMPL");
        deployment.coinVersion = readStringOrDefaultToEmpty(json, "COIN_VERSION");
        deployment.buySupplyWithSwapRouterHook = readAddressOrDefaultToZero(json, "BUY_SUPPLY_WITH_SWAP_ROUTER_HOOK");
        deployment.zoraV4CoinHook = readAddressOrDefaultToZero(json, "ZORA_V4_COIN_HOOK");
        deployment.zoraV4CoinHookSalt = readBytes32OrDefaultToZero(json, "ZORA_V4_COIN_HOOK_SALT");
        deployment.creatorCoinImpl = readAddressOrDefaultToZero(json, "CREATOR_COIN_IMPL");
        deployment.hookUpgradeGate = readAddressOrDefaultToZero(json, "HOOK_UPGRADE_GATE");
        deployment.zoraHookRegistry = readAddressOrDefaultToZero(json, "ZORA_HOOK_REGISTRY");
        deployment.trustedMsgSenderLookup = readAddressOrDefaultToZero(json, "TRUSTED_MSG_SENDER_LOOKUP");
        deployment.zoraLimitOrderBook = readAddressOrDefaultToZero(json, "ZORA_LIMIT_ORDER_BOOK");
        deployment.zoraRouter = readAddressOrDefaultToZero(json, "ZORA_ROUTER");
    }

    function deployCoinV4Impl() internal returns (ContentCoin) {
        return
            new ContentCoin({
                protocolRewardRecipient_: getZoraRecipient(),
                protocolRewards_: PROTOCOL_REWARDS,
                poolManager_: IPoolManager(getUniswapV4PoolManager()),
                airlock_: getDopplerAirlock()
            });
    }

    function deployCreatorCoinImpl() internal returns (CreatorCoin) {
        return
            new CreatorCoin({
                protocolRewardRecipient_: getZoraRecipient(),
                protocolRewards_: PROTOCOL_REWARDS,
                poolManager_: IPoolManager(getUniswapV4PoolManager()),
                airlock_: getDopplerAirlock()
            });
    }

    function deployZoraFactoryImpl(address coinV4Impl_, address creatorCoinImpl_, address hook_, address zoraHookRegistry_) internal returns (ZoraFactoryImpl) {
        return new ZoraFactoryImpl({coinV4Impl_: coinV4Impl_, creatorCoinImpl_: creatorCoinImpl_, hook_: hook_, zoraHookRegistry_: zoraHookRegistry_});
    }

    function deployBuySupplyWithV4SwapHook(CoinsDeployment memory deployment) internal returns (BuySupplyWithV4SwapHook) {
        return
            new BuySupplyWithV4SwapHook({
                _factory: IZoraFactory(deployment.zoraFactory),
                _swapRouter: getUniswapSwapRouter(),
                _poolManager: getUniswapV4PoolManager()
            });
    }

    function deployUpgradeGate(CoinsDeployment memory deployment) internal returns (CoinsDeployment memory) {
        deployment.hookUpgradeGate = address(new HookUpgradeGate(getProxyAdmin()));

        return deployment;
    }

    function deployTrustedMsgSenderLookup(CoinsDeployment memory deployment) internal returns (CoinsDeployment memory) {
        // Deploy the contract directly using constructor
        // Include swap router address if it has been computed (for deterministic deployment)
        deployment.trustedMsgSenderLookup = address(
            new TrustedMsgSenderProviderLookup(getDefaultTrustedMessageSenders(deployment.zoraRouter), getProxyAdmin())
        );

        return deployment;
    }

    function deployZoraV4CoinHook(CoinsDeployment memory deployment) internal returns (IHooks hook, bytes32 salt) {
        require(deployment.trustedMsgSenderLookup != address(0), "Trusted message sender lookup not deployed");

        return
            HooksDeployment.deployHookWithExistingOrNewSalt(
                HooksDeployment.FOUNDRY_SCRIPT_ADDRESS,
                HooksDeployment.makeHookCreationCode(
                    getUniswapV4PoolManager(),
                    deployment.zoraFactory,
                    ITrustedMsgSenderProviderLookup(deployment.trustedMsgSenderLookup),
                    deployment.hookUpgradeGate,
                    deployment.zoraLimitOrderBook,
                    deployment.zoraHookRegistry
                ),
                deployment.zoraV4CoinHookSalt
            );
    }

    function getDefaultTrustedMessageSenders(address zoraRouter) internal view returns (address[] memory) {
        require(zoraRouter != address(0), "Swap router address must be computed first");

        address[] memory trustedMessageSenders = new address[](3);
        trustedMessageSenders[0] = getUniswapUniversalRouter();
        trustedMessageSenders[1] = getUniswapV4PositionManager();
        trustedMessageSenders[2] = zoraRouter;

        return trustedMessageSenders;
    }

    function deployFactoryImpl(CoinsDeployment memory deployment) internal returns (address) {
        return
            address(
                deployZoraFactoryImpl({
                    coinV4Impl_: deployment.coinV4Impl,
                    creatorCoinImpl_: deployment.creatorCoinImpl,
                    hook_: deployment.zoraV4CoinHook,
                    zoraHookRegistry_: deployment.zoraHookRegistry
                })
            );
    }

    function deployImpls(CoinsDeployment memory deployment) internal returns (CoinsDeployment memory) {
        // Deploy implementation contracts

        // Deploy trusted message sender lookup first
        deployment = deployTrustedMsgSenderLookup(deployment);

        // Deploy hook first, then use its address for coin v4 impl
        console.log("deploying content coin hook");
        (IHooks zoraV4CoinHook, bytes32 usedSalt) = deployZoraV4CoinHook(deployment);
        deployment.zoraV4CoinHook = address(zoraV4CoinHook);
        deployment.zoraV4CoinHookSalt = usedSalt;

        deployment.coinV4Impl = address(deployCoinV4Impl());
        deployment.creatorCoinImpl = address(deployCreatorCoinImpl());
        deployment.zoraFactoryImpl = deployFactoryImpl(deployment);
        deployment.coinVersion = IVersionedContract(deployment.coinV4Impl).contractVersion();
        // deployment.buySupplyWithSwapRouterHook = address(deployBuySupplyWithSwapRouterHook(deployment));

        return deployment;
    }

    function deployHooks(CoinsDeployment memory deployment) internal returns (CoinsDeployment memory) {
        // Deploy trusted message sender lookup first
        deployment = deployTrustedMsgSenderLookup(deployment);

        // Deploy hook first, then use its address for coin v4 impl
        (IHooks zoraV4CoinHook, bytes32 usedSalt) = deployZoraV4CoinHook(deployment);
        deployment.zoraV4CoinHook = address(zoraV4CoinHook);
        deployment.zoraV4CoinHookSalt = usedSalt;

        deployment.zoraFactoryImpl = deployFactoryImpl(deployment);

        return deployment;
    }

    function deployZoraDeterministic(CoinsDeployment memory deployment, DeterministicDeployerAndCaller deployer) internal {
        // read previously saved deterministic config
        DeterministicContractConfig memory zoraConfig = readDeterministicContractConfig("zoraFactory");

        deployment = deployImpls(deployment);

        if (deployment.zoraFactoryImpl.code.length == 0) {
            revert("Factory Impl not yet deployed. Make sure to deploy it with DeployImpl.s.sol");
        }

        // build upgrade to and call for factory, with init call
        bytes memory upgradeToAndCall = abi.encodeWithSelector(
            UUPSUpgradeable.upgradeToAndCall.selector,
            deployment.zoraFactoryImpl,
            abi.encodeWithSelector(ZoraFactoryImpl.initialize.selector, getProxyAdmin())
        );

        // sign deployment with turnkey account
        bytes memory signature = signDeploymentWithTurnkey(zoraConfig, upgradeToAndCall, deployer);

        printVerificationCommand(zoraConfig);

        deployment.zoraFactory = deployer.permitSafeCreate2AndCall(
            signature,
            zoraConfig.salt,
            zoraConfig.creationCode,
            upgradeToAndCall,
            zoraConfig.deployedAddress
        );

        // validate that the zora factory owner is the proxy admin
        require(ZoraFactoryImpl(deployment.zoraFactory).owner() == getProxyAdmin(), "Zora factory owner is not the proxy admin");
    }

    function deployFactoryNonDeterministic(CoinsDeployment memory deployment) internal returns (ZoraFactory) {
        address owner = getProxyAdmin();

        // Use deterministic deployment so limit order contracts can discover the factory address
        deployFactoryDeterministic(deployment, owner);

        saveDeployment(deployment);

        return ZoraFactory(payable(deployment.zoraFactory));
    }

    function printUpgradeFactoryCommand(CoinsDeployment memory deployment) internal view {
        // build upgrade to and call for factory, with init call
        bytes memory call = abi.encodeWithSelector(UUPSUpgradeable.upgradeToAndCall.selector, deployment.zoraFactoryImpl, "");

        address proxyAdmin = getProxyAdmin();

        address target = address(deployment.zoraFactory);

        // print the details for upgrading:

        console.log("To upgrade the factory, this is the call information:");

        console.log("Multisig:", proxyAdmin);
        console.log("Target (the factory proxy):", target);
        console.log("Upgrade call:");
        console.logBytes(call);
        console.log("Function to call: upgradeToAndCall");
        // concat the args into a string, factoryImpl, ""
        console.log("Args: ", string.concat(vm.toString(deployment.zoraFactoryImpl), ",", '"'));
    }

    // Limit Order Book Deterministic Deployment Functions

    function computeLimitOrderBookAddress(
        address poolManager,
        address zoraFactory,
        address zoraHookRegistry,
        address owner,
        address weth
    ) internal pure returns (address) {
        bytes memory creationCode = abi.encodePacked(
            type(ZoraLimitOrderBook).creationCode,
            abi.encode(poolManager, zoraFactory, zoraHookRegistry, owner, weth)
        );

        return Create2.computeAddress(LIMIT_ORDER_BOOK_SALT, keccak256(creationCode), address(ImmutableCreate2FactoryUtils.IMMUTABLE_CREATE2_FACTORY));
    }

    function deployLimitOrderBookDeterministic(
        address poolManager,
        address zoraFactory,
        address zoraHookRegistry,
        address owner,
        address weth
    ) internal returns (address) {
        require(poolManager != address(0), "Pool manager cannot be zero address");
        require(zoraFactory != address(0), "Zora factory cannot be zero address");
        require(zoraHookRegistry != address(0), "Zora hook registry cannot be zero address");
        require(owner != address(0), "Owner cannot be zero address");
        require(weth != address(0), "WETH cannot be zero address");

        bytes memory creationCode = abi.encodePacked(
            type(ZoraLimitOrderBook).creationCode,
            abi.encode(poolManager, zoraFactory, zoraHookRegistry, owner, weth)
        );

        address deployed = ImmutableCreate2FactoryUtils.safeCreate2OrGetExisting(LIMIT_ORDER_BOOK_SALT, creationCode);

        return deployed;
    }

    function computeSwapRouterAddress(
        address poolManager,
        address zoraLimitOrderBook,
        address swapRouter,
        address permit2,
        address owner
    ) internal pure returns (address) {
        bytes memory creationCode = abi.encodePacked(
            type(SwapWithLimitOrders).creationCode,
            abi.encode(poolManager, zoraLimitOrderBook, swapRouter, permit2, owner)
        );

        return Create2.computeAddress(SWAP_ROUTER_SALT, keccak256(creationCode), address(ImmutableCreate2FactoryUtils.IMMUTABLE_CREATE2_FACTORY));
    }

    function deploySwapRouterDeterministic(
        address poolManager,
        address zoraLimitOrderBook,
        address swapRouter,
        address permit2,
        address owner
    ) internal returns (address) {
        require(poolManager != address(0), "Pool manager cannot be zero address");
        require(zoraLimitOrderBook != address(0), "Zora limit order book cannot be zero address");
        require(swapRouter != address(0), "Swap router cannot be zero address");
        require(permit2 != address(0), "Permit2 cannot be zero address");
        require(owner != address(0), "Owner cannot be zero address");

        bytes memory creationCode = abi.encodePacked(
            type(SwapWithLimitOrders).creationCode,
            abi.encode(poolManager, zoraLimitOrderBook, swapRouter, permit2, owner)
        );

        address deployed = ImmutableCreate2FactoryUtils.safeCreate2OrGetExisting(SWAP_ROUTER_SALT, creationCode);

        return deployed;
    }

    // Non-deterministic Deployment Functions (for dev environments)

    function deployLimitOrderBook(address poolManager, address zoraFactory, address zoraHookRegistry, address owner, address weth) internal returns (address) {
        return address(new ZoraLimitOrderBook(poolManager, zoraFactory, zoraHookRegistry, owner, weth));
    }

    function deploySwapRouter(address poolManager, address zoraLimitOrderBook, address swapRouter, address permit2, address owner) internal returns (address) {
        return address(new SwapWithLimitOrders(IPoolManager(poolManager), IZoraLimitOrderBook(zoraLimitOrderBook), ISwapRouter(swapRouter), permit2, owner));
    }

    // Factory Deterministic Deployment Functions

    function computeProxyShimAddress() internal pure returns (address) {
        bytes memory creationCode = type(ProxyShim).creationCode;

        return Create2.computeAddress(PROXY_SHIM_SALT, keccak256(creationCode), address(ImmutableCreate2FactoryUtils.IMMUTABLE_CREATE2_FACTORY));
    }

    function deployProxyShimDeterministic() internal returns (address) {
        bytes memory creationCode = type(ProxyShim).creationCode;

        address deployed = ImmutableCreate2FactoryUtils.safeCreate2OrGetExisting(PROXY_SHIM_SALT, creationCode);

        return deployed;
    }

    function computeFactoryAddress(address proxyShimAddress) internal pure returns (address) {
        bytes memory creationCode = abi.encodePacked(type(ZoraFactory).creationCode, abi.encode(proxyShimAddress));

        return Create2.computeAddress(FACTORY_SALT, keccak256(creationCode), address(ImmutableCreate2FactoryUtils.IMMUTABLE_CREATE2_FACTORY));
    }

    function deployFactoryDeterministic(CoinsDeployment memory deployment, address owner) internal returns (address) {
        require(owner != address(0), "Owner cannot be zero address");

        // Deploy ProxyShim deterministically
        address proxyShim = deployProxyShimDeterministic();

        // Deploy ZoraFactory proxy deterministically
        bytes memory creationCode = abi.encodePacked(type(ZoraFactory).creationCode, abi.encode(proxyShim));

        address factoryProxy = ImmutableCreate2FactoryUtils.safeCreate2OrGetExisting(FACTORY_SALT, creationCode);

        deployment.zoraFactory = factoryProxy;

        // Deploy implementations
        deployment = deployImpls(deployment);

        // Upgrade to real implementation
        UUPSUpgradeable(deployment.zoraFactory).upgradeToAndCall(deployment.zoraFactoryImpl, "");

        // Initialize
        ZoraFactoryImpl(deployment.zoraFactory).initialize(owner);

        return factoryProxy;
    }

    // Hook Registry Deterministic Deployment Functions

    function computeHookRegistryAddress() internal pure returns (address) {
        bytes memory creationCode = type(ZoraHookRegistry).creationCode;

        return Create2.computeAddress(HOOK_REGISTRY_SALT, keccak256(creationCode), address(ImmutableCreate2FactoryUtils.IMMUTABLE_CREATE2_FACTORY));
    }

    function deployHookRegistryDeterministic(address[] memory initialOwners) internal returns (address) {
        require(initialOwners.length > 0, "Initial owners cannot be empty");

        bytes memory creationCode = type(ZoraHookRegistry).creationCode;

        address deployed = ImmutableCreate2FactoryUtils.safeCreate2OrGetExisting(HOOK_REGISTRY_SALT, creationCode);

        // Initialize if not already initialized
        ZoraHookRegistry registry = ZoraHookRegistry(deployed);
        // Check if already initialized by trying to call a function that requires initialization
        try registry.isRegisteredHook(address(0)) {
            // Already initialized, skip
        } catch {
            // Not initialized yet, initialize now
            registry.initialize(initialOwners);
        }

        return deployed;
    }
}
