// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IWETH} from "../../src/interfaces/IWETH.sol";
import {IAirlock} from "../../src/interfaces/IAirlock.sol";
import {INonfungiblePositionManager} from "../../src/interfaces/INonfungiblePositionManager.sol";
import {ISwapRouter} from "../../src/interfaces/ISwapRouter.sol";
import {IUniswapV3Factory} from "../../src/interfaces/IUniswapV3Factory.sol";
import {IProtocolRewards} from "../../src/interfaces/IProtocolRewards.sol";
import {ProtocolRewards} from "./ProtocolRewards.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {ZoraV4CoinHook} from "../../src/hooks/ZoraV4CoinHook.sol";
import {HooksDeployment} from "../../src/libs/HooksDeployment.sol";
import {ProxyShim} from "../../src/utils/ProxyShim.sol";
import {ICoin} from "../../src/interfaces/ICoin.sol";
import {UniV4SwapHelper} from "../../src/libs/UniV4SwapHelper.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {IUniversalRouter} from "@uniswap/universal-router/contracts/interfaces/IUniversalRouter.sol";
import {IV4Quoter} from "@uniswap/v4-periphery/src/interfaces/IV4Quoter.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {ContractAddresses} from "./ContractAddresses.sol";
import {HookUpgradeGate} from "../../src/hooks/HookUpgradeGate.sol";
import {ZoraHookRegistry} from "../../src/hook-registry/ZoraHookRegistry.sol";
import {IZoraFactory} from "../../src/interfaces/IZoraFactory.sol";
import {ZoraFactoryImpl} from "../../src/ZoraFactoryImpl.sol";
import {ZoraFactory} from "../../src/proxy/ZoraFactory.sol";
import {ContentCoin} from "../../src/ContentCoin.sol";
import {CreatorCoin} from "../../src/CreatorCoin.sol";
import {CoinConfigurationVersions} from "../../src/libs/CoinConfigurationVersions.sol";
import {CoinConstants} from "../../src/libs/CoinConstants.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {MockZoraLimitOrderBook} from "../mocks/MockZoraLimitOrderBook.sol";
import {ITrustedMsgSenderProviderLookup} from "../../src/interfaces/ITrustedMsgSenderProviderLookup.sol";
import {TrustedSenderTestHelper} from "./TrustedSenderTestHelper.sol";

// Hookmate imports for non-forked testing
import {V4PoolManagerDeployer} from "./hookmate/artifacts/V4PoolManager.sol";
import {V4QuoterDeployer} from "./hookmate/artifacts/V4Quoter.sol";
import {Permit2Deployer} from "./hookmate/artifacts/Permit2.sol";
import {DeployHelper} from "./hookmate/artifacts/DeployHelper.sol";
import {AddressConstants} from "./hookmate/constants/AddressConstants.sol";
import {UniversalRouterDeployer, RouterParameters} from "./hookmate/artifacts/UniversalRouter.sol";
import {MockAirlock} from "../mocks/MockAirlock.sol";
import {MockSwapRouter} from "../mocks/MockSwapRouter.sol";
import {SimpleERC20} from "../mocks/SimpleERC20.sol";

/**
 * @title V4TestSetup
 * @notice Shared base test contract for Uniswap V4 infrastructure setup
 * @dev This contract provides common setup and utilities for both coins and limit-orders test suites.
 *      It includes fork management, V4 infrastructure deployment, and helper functions.
 */
contract V4TestSetup is Test, ContractAddresses {
    using stdStorage for StdStorage;

    // Constants
    int24 internal constant USDC_TICK_LOWER = 57200;
    int24 internal constant DEFAULT_DISCOVERY_TICK_LOWER = CoinConstants.DEFAULT_DISCOVERY_TICK_LOWER;
    int24 internal constant DEFAULT_DISCOVERY_TICK_UPPER = CoinConstants.DEFAULT_DISCOVERY_TICK_UPPER;
    uint16 internal constant DEFAULT_NUM_DISCOVERY_POSITIONS = CoinConstants.DEFAULT_NUM_DISCOVERY_POSITIONS;
    uint256 internal constant DEFAULT_DISCOVERY_SUPPLY_SHARE = CoinConstants.DEFAULT_DISCOVERY_SUPPLY_SHARE;
    string internal constant DEFAULT_NAME = "Testcoin";
    string internal constant DEFAULT_SYMBOL = "TEST";

    struct Users {
        address factoryOwner;
        address feeRecipient;
        address creator;
        address platformReferrer;
        address buyer;
        address seller;
        address coinRecipient;
        address tradeReferrer;
        address dopplerRecipient;
    }

    // Fork management
    uint256 internal forkId;

    // Tokens
    IERC20Metadata internal zoraToken;
    IERC20Metadata internal usdc;
    IWETH internal weth;

    // Protocol contracts
    ProtocolRewards internal protocolRewards;
    IUniswapV3Factory internal v3Factory;
    INonfungiblePositionManager internal nonfungiblePositionManager;
    ISwapRouter internal swapRouter;
    IAirlock internal airlock;

    // Uniswap V4 infrastructure
    IPermit2 internal permit2;
    IUniversalRouter internal router;
    IPoolManager internal poolManager;
    IV4Quoter internal quoter;

    // Zora protocol contracts
    ContentCoin internal coinV4Impl;
    CreatorCoin internal creatorCoinImpl;
    ZoraFactoryImpl internal factoryImpl;
    IZoraFactory internal factory;
    ZoraV4CoinHook internal hook;
    HookUpgradeGate internal hookUpgradeGate;
    ZoraHookRegistry internal zoraHookRegistry;
    MockZoraLimitOrderBook internal mockZoraLimitOrderBook;

    // Deployed coins (for convenience in tests)
    ContentCoin internal coinV4;

    // Test users
    Users internal users;

    // ============================================
    // Setup Functions
    // ============================================
    // Note: No setUp() function - inheriting contracts must implement their own
    function _setUpWithBlockNumber(uint256 forkBlockNumber) internal {
        mockZoraLimitOrderBook = new MockZoraLimitOrderBook();
        _setUpWithBlockNumber(forkBlockNumber, address(mockZoraLimitOrderBook));
    }

    function _setUpWithBlockNumber(uint256 forkBlockNumber, address _limitOrderBook) internal {
        forkId = vm.createSelectFork("base", forkBlockNumber);

        weth = IWETH(WETH_ADDRESS);
        usdc = IERC20Metadata(USDC_ADDRESS);
        zoraToken = IERC20Metadata(ZORA_TOKEN_ADDRESS);
        v3Factory = IUniswapV3Factory(V3_FACTORY);
        nonfungiblePositionManager = INonfungiblePositionManager(NONFUNGIBLE_POSITION_MANAGER);
        swapRouter = ISwapRouter(SWAP_ROUTER);
        airlock = IAirlock(DOPPLER_AIRLOCK);
        protocolRewards = new ProtocolRewards();
        permit2 = IPermit2(V4_PERMIT2);
        router = IUniversalRouter(UNIVERSAL_ROUTER);
        poolManager = IPoolManager(V4_POOL_MANAGER);
        quoter = IV4Quoter(V4_QUOTER);
        users = Users({
            factoryOwner: makeAddr("factoryOwner"),
            feeRecipient: makeAddr("feeRecipient"),
            creator: makeAddr("creator"),
            platformReferrer: makeAddr("platformReferrer"),
            buyer: makeAddr("buyer"),
            seller: makeAddr("seller"),
            coinRecipient: makeAddr("coinRecipient"),
            tradeReferrer: makeAddr("tradeReferrer"),
            dopplerRecipient: makeAddr("dopplerRecipient")
        });

        ProxyShim mockUpgradeableImpl = new ProxyShim();
        factory = IZoraFactory(address(new ZoraFactory(address(mockUpgradeableImpl))));

        hookUpgradeGate = new HookUpgradeGate(users.factoryOwner);

        zoraHookRegistry = new ZoraHookRegistry();

        address[] memory initialOwners = new address[](2);
        initialOwners[0] = users.factoryOwner;
        initialOwners[1] = address(factory);
        zoraHookRegistry.initialize(initialOwners);

        _deployHooks(_limitOrderBook);

        coinV4Impl = new ContentCoin(users.feeRecipient, address(protocolRewards), IPoolManager(V4_POOL_MANAGER), DOPPLER_AIRLOCK);

        creatorCoinImpl = new CreatorCoin(users.feeRecipient, address(protocolRewards), IPoolManager(V4_POOL_MANAGER), DOPPLER_AIRLOCK);

        factoryImpl = new ZoraFactoryImpl(address(coinV4Impl), address(creatorCoinImpl), address(hook), address(zoraHookRegistry));
        UUPSUpgradeable(address(factory)).upgradeToAndCall(address(factoryImpl), "");
        factory = IZoraFactory(address(factory));

        ZoraFactoryImpl(address(factory)).initialize(users.factoryOwner);

        vm.label(address(factory), "ZORA_FACTORY");
        vm.label(address(protocolRewards), "PROTOCOL_REWARDS");
        vm.label(address(nonfungiblePositionManager), "NONFUNGIBLE_POSITION_MANAGER");
        vm.label(address(v3Factory), "V3_FACTORY");
        vm.label(address(swapRouter), "SWAP_ROUTER");
        vm.label(address(weth), "WETH");
        vm.label(address(usdc), "USDC");
        vm.label(address(airlock), "AIRLOCK");
        vm.label(address(zoraToken), "$ZORA");
        vm.label(address(V4_POOL_MANAGER), "V4_POOL_MANAGER");
        vm.label(address(V4_POSITION_MANAGER), "V4_POSITION_MANAGER");
        vm.label(address(V4_QUOTER), "V4_QUOTER");
        vm.label(address(V4_PERMIT2), "V4_PERMIT2");
        vm.label(address(UNIVERSAL_ROUTER), "UNIVERSAL_ROUTER");
        vm.label(address(hook), "HOOK");
        vm.label(address(mockZoraLimitOrderBook), "LIMIT_ORDER_BOOK");
    }

    function _setUpNonForked() internal {
        mockZoraLimitOrderBook = new MockZoraLimitOrderBook();
        _setUpNonForked(address(mockZoraLimitOrderBook));
    }

    function _setUpNonForked(address limitOrderBook) internal {
        // Initialize users first
        users = Users({
            factoryOwner: makeAddr("factoryOwner"),
            feeRecipient: makeAddr("feeRecipient"),
            creator: makeAddr("creator"),
            platformReferrer: makeAddr("platformReferrer"),
            buyer: makeAddr("buyer"),
            seller: makeAddr("seller"),
            coinRecipient: makeAddr("coinRecipient"),
            tradeReferrer: makeAddr("tradeReferrer"),
            dopplerRecipient: makeAddr("dopplerRecipient")
        });

        // Deploy mock airlock with the dopplerRecipient as owner (for doppler rewards)
        MockAirlock mockAirlock = new MockAirlock(users.dopplerRecipient);

        // Deploy V4 infrastructure using hookmate
        _deployV4InfrastructureNonForked();

        // Deploy mock ZORA token at the correct address
        deployCodeTo("SimpleERC20.sol:SimpleERC20", abi.encode("ZORA", "$ZORA"), ZORA_TOKEN_ADDRESS);
        zoraToken = IERC20Metadata(ZORA_TOKEN_ADDRESS);

        // Fund the pool manager with ZORA tokens
        deal(address(zoraToken), address(poolManager), 1_000_000_000e18);

        // Deploy protocol rewards
        protocolRewards = new ProtocolRewards();

        // Deploy factory proxy
        ProxyShim mockUpgradeableImpl = new ProxyShim();
        factory = IZoraFactory(address(new ZoraFactory(address(mockUpgradeableImpl))));

        // Deploy hook upgrade gate
        hookUpgradeGate = new HookUpgradeGate(users.factoryOwner);

        // Deploy zora hook registry
        zoraHookRegistry = new ZoraHookRegistry();
        address[] memory initialOwners = new address[](2);
        initialOwners[0] = users.factoryOwner;
        initialOwners[1] = address(factory);
        zoraHookRegistry.initialize(initialOwners);

        // Deploy limit order book
        mockZoraLimitOrderBook = new MockZoraLimitOrderBook();

        // Deploy hooks for non-forked environment
        _deployHooksNonForked(limitOrderBook);

        // Deploy coin implementations
        coinV4Impl = new ContentCoin(users.feeRecipient, address(protocolRewards), poolManager, address(mockAirlock));
        creatorCoinImpl = new CreatorCoin(users.feeRecipient, address(protocolRewards), poolManager, address(mockAirlock));

        // Deploy and initialize factory implementation
        factoryImpl = new ZoraFactoryImpl(address(coinV4Impl), address(creatorCoinImpl), address(hook), address(zoraHookRegistry));
        UUPSUpgradeable(address(factory)).upgradeToAndCall(address(factoryImpl), "");
        ZoraFactoryImpl(address(factory)).initialize(users.factoryOwner);

        // Deploy mock V3 swap router for non-forked tests
        swapRouter = ISwapRouter(address(new MockSwapRouter()));

        // Labels for easier debugging
        vm.label(address(factory), "ZORA_FACTORY");
        vm.label(address(protocolRewards), "PROTOCOL_REWARDS");
        vm.label(address(poolManager), "V4_POOL_MANAGER");
        vm.label(address(permit2), "V4_PERMIT2");
        vm.label(address(router), "UNIVERSAL_ROUTER");
        vm.label(address(hook), "HOOK");
        vm.label(address(mockAirlock), "MOCK_AIRLOCK");
        vm.label(address(mockZoraLimitOrderBook), "LIMIT_ORDER_BOOK");
        vm.label(address(swapRouter), "MOCK_SWAP_ROUTER");
    }

    // ============================================
    // V4 Infrastructure Deployment (Non-Forked)
    // ============================================

    function _deployV4InfrastructureNonForked() internal {
        // Deploy Permit2 to canonical address
        _deployPermit2NonForked();

        // Deploy PoolManager
        _deployPoolManagerNonForked();

        // Deploy Quoter
        _deployQuoterNonForked();

        // Deploy Universal Router
        _deployUniversalRouterNonForked();
    }

    function _deployPermit2NonForked() internal {
        address permit2Address = AddressConstants.getPermit2Address();

        if (permit2Address.code.length > 0) {
            // Permit2 is already deployed
        } else {
            address tempDeployAddress = address(Permit2Deployer.deploy());
            vm.etch(permit2Address, tempDeployAddress.code);
        }

        permit2 = IPermit2(permit2Address);
    }

    function _deployPoolManagerNonForked() internal {
        if (block.chainid == 31337) {
            poolManager = IPoolManager(address(V4PoolManagerDeployer.deploy(address(0x4444))));
        } else {
            poolManager = IPoolManager(AddressConstants.getPoolManagerAddress(block.chainid));
        }

        deal(address(poolManager), 10000 ether);
    }

    function _deployQuoterNonForked() internal {
        quoter = IV4Quoter(V4QuoterDeployer.deploy(address(poolManager)));
    }

    function _deployUniversalRouterNonForked() internal {
        RouterParameters memory params = RouterParameters({
            permit2: address(permit2),
            weth9: address(0),
            v2Factory: address(0),
            v3Factory: address(0),
            pairInitCodeHash: bytes32(0),
            poolInitCodeHash: bytes32(0),
            v4PoolManager: address(poolManager),
            v3NFTPositionManager: address(0),
            v4PositionManager: address(0)
        });
        router = IUniversalRouter(UniversalRouterDeployer.deploy(params));
    }

    // ============================================
    // Hook Deployment
    // ============================================

    function getSalt(ITrustedMsgSenderProviderLookup trustedMsgSenderLookup, address limitOrderBook) public returns (bytes32 hookSalt) {
        address deployer = address(this);

        (, hookSalt) = HooksDeployment.mineForCoinSalt(
            deployer,
            V4_POOL_MANAGER,
            address(factory),
            trustedMsgSenderLookup,
            address(hookUpgradeGate),
            limitOrderBook,
            address(zoraHookRegistry)
        );
    }

    function _deployHooks(address limitOrderBook) internal {
        address[] memory trustedMessageSenders = new address[](2);
        trustedMessageSenders[0] = UNIVERSAL_ROUTER;
        trustedMessageSenders[1] = V4_POSITION_MANAGER;

        ITrustedMsgSenderProviderLookup trustedMsgSenderLookup = TrustedSenderTestHelper.deployTrustedMessageSender(users.factoryOwner, trustedMessageSenders);

        bytes32 hookSalt = getSalt(trustedMsgSenderLookup, limitOrderBook);

        hook = ZoraV4CoinHook(
            payable(
                address(
                    HooksDeployment.deployHookWithSalt(
                        HooksDeployment.makeHookCreationCode(
                            V4_POOL_MANAGER,
                            address(factory),
                            trustedMsgSenderLookup,
                            address(hookUpgradeGate),
                            limitOrderBook,
                            address(zoraHookRegistry)
                        ),
                        hookSalt
                    )
                )
            )
        );

        address[] memory hooks = new address[](1);
        hooks[0] = address(hook);
        string[] memory tags = new string[](1);
        tags[0] = "CoinHook";
        vm.prank(users.factoryOwner);
        zoraHookRegistry.registerHooks(hooks, tags);
    }

    function _deployHooksNonForked(address limitOrderBook) internal {
        address[] memory trustedMessageSenders = new address[](1);
        trustedMessageSenders[0] = address(router);

        ITrustedMsgSenderProviderLookup trustedMsgSenderLookup = TrustedSenderTestHelper.deployTrustedMessageSender(users.factoryOwner, trustedMessageSenders);

        // Use proper salt mining for hook deployment
        address deployer = address(this);
        (, bytes32 salt) = HooksDeployment.mineForCoinSalt(
            deployer,
            address(poolManager),
            address(factory),
            trustedMsgSenderLookup,
            address(hookUpgradeGate),
            limitOrderBook,
            address(zoraHookRegistry)
        );

        bytes memory hookCreationCode = HooksDeployment.makeHookCreationCode(
            address(poolManager),
            address(factory),
            trustedMsgSenderLookup,
            address(hookUpgradeGate),
            limitOrderBook,
            address(zoraHookRegistry)
        );

        hook = ZoraV4CoinHook(payable(DeployHelper.deploy(hookCreationCode, salt)));

        address[] memory hooks = new address[](1);
        hooks[0] = address(hook);
        string[] memory tags = new string[](1);
        tags[0] = "CoinHook";
        vm.prank(users.factoryOwner);
        zoraHookRegistry.registerHooks(hooks, tags);
    }

    function _deployFeeEstimatorHook(address hooks) internal {
        // Deploy a new lookup with the same trusted senders
        address[] memory trustedMessageSenders = new address[](2);
        trustedMessageSenders[0] = UNIVERSAL_ROUTER;
        trustedMessageSenders[1] = V4_POSITION_MANAGER;
        ITrustedMsgSenderProviderLookup newLookup = TrustedSenderTestHelper.deployTrustedMessageSender(users.factoryOwner, trustedMessageSenders);

        deployCodeTo(
            "FeeEstimatorHook.sol",
            abi.encode(address(poolManager), address(factory), newLookup, hookUpgradeGate, _getLimitOrderBookAddress(), address(zoraHookRegistry)),
            hooks
        );
    }

    function _getLimitOrderBookAddress() internal view virtual returns (address) {
        return address(mockZoraLimitOrderBook);
    }

    // ============================================
    // Coin Deployment Helpers
    // ============================================

    function _defaultPoolConfig(address currency) internal pure returns (bytes memory) {
        return CoinConfigurationVersions.defaultDopplerMultiCurveUniV4(currency);
    }

    function _deployV4Coin(address currency) internal returns (ICoin) {
        bytes32 salt = keccak256(abi.encode(bytes("randomSalt")));
        return _deployV4Coin(currency, address(0), salt);
    }

    function _deployV4Coin(address currency, address createReferral, bytes32 salt) internal returns (ICoin) {
        address[] memory owners = new address[](1);
        owners[0] = users.creator;

        bytes memory poolConfig = _defaultPoolConfig(currency);

        vm.prank(users.creator);
        (address coinAddress, ) = factory.deploy(
            users.creator,
            owners,
            "https://test.com",
            DEFAULT_NAME,
            DEFAULT_SYMBOL,
            poolConfig,
            createReferral,
            address(0),
            bytes(""),
            salt
        );

        coinV4 = ContentCoin(payable(coinAddress));
        return coinV4;
    }

    function _deployV4Coin() internal returns (ICoin) {
        // deploy with eth and no referral
        return _deployV4Coin(address(0), address(0), bytes32(0));
    }

    function _deployCoinUSDCPair() internal {
        bytes memory poolConfig_ = _defaultPoolConfig(USDC_ADDRESS);
        vm.prank(users.creator);
        (address coinAddress, ) = factory.deploy(
            users.creator,
            _getDefaultOwners(),
            "https://test.com",
            "Testcoin",
            "TEST",
            poolConfig_,
            users.platformReferrer,
            0
        );

        vm.label(coinAddress, "COIN");
    }

    // ============================================
    // Swap Helpers
    // ============================================

    function _swapSomeCurrencyForCoin(ICoin _coin, address currency, uint128 amountIn, address trader) internal {
        _swapSomeCurrencyForCoin(_coin.getPoolKey(), _coin, currency, amountIn, trader);
    }

    function _swapSomeCurrencyForCoin(PoolKey memory poolKey, ICoin _coin, address currency, uint128 amountIn, address trader) internal {
        uint128 minAmountOut = uint128(0);

        (bytes memory commands, bytes[] memory inputs) = UniV4SwapHelper.buildExactInputSingleSwapCommand(
            currency,
            amountIn,
            address(_coin),
            minAmountOut,
            poolKey,
            bytes("")
        );

        vm.startPrank(trader);
        if (currency != address(0)) {
            UniV4SwapHelper.approveTokenWithPermit2(permit2, address(router), currency, amountIn, uint48(block.timestamp + 1 days));
        }

        uint256 value = currency == address(0) ? amountIn : 0;

        // Execute the swap
        uint256 deadline = block.timestamp + 20;
        router.execute{value: value}(commands, inputs, deadline);

        vm.stopPrank();
    }

    function _swapSomeCoinForCurrency(ICoin _coin, address currency, uint128 amountIn, address trader) internal {
        uint128 minAmountOut = uint128(0);

        (bytes memory commands, bytes[] memory inputs) = UniV4SwapHelper.buildExactInputSingleSwapCommand(
            address(_coin),
            amountIn,
            currency,
            minAmountOut,
            _coin.getPoolKey(),
            bytes("")
        );

        vm.startPrank(trader);
        UniV4SwapHelper.approveTokenWithPermit2(permit2, address(router), address(_coin), amountIn, uint48(block.timestamp + 1 days));

        // Execute the swap
        uint256 deadline = block.timestamp + 20;
        router.execute(commands, inputs, deadline);

        vm.stopPrank();
    }

    // ============================================
    // Common Helper Functions
    // ============================================

    function _calculateExpectedFee(uint256 ethAmount) internal pure returns (uint256) {
        uint256 feeBps = 100; // 1%
        return (ethAmount * feeBps) / 10_000;
    }

    function dealUSDC(address to, uint256 numUSDC) internal returns (uint256) {
        uint256 amount = numUSDC * 1e6;
        deal(address(usdc), to, amount);
        return amount;
    }

    function _getDefaultOwners() internal view returns (address[] memory owners) {
        owners = new address[](1);
        owners[0] = users.creator;
    }

    function dopplerFeeRecipient() internal view returns (address) {
        return airlock.owner();
    }

    function _generatePoolConfig(address currency_) internal pure returns (bytes memory) {
        return CoinConfigurationVersions.defaultDopplerMultiCurveUniV4(currency_);
    }

    function _generatePoolConfig(
        uint8 version_,
        address currency_,
        int24 tickLower_,
        int24 tickUpper_,
        uint16 numDiscoveryPositions_,
        uint256 maxDiscoverySupplyShare_
    ) internal pure returns (bytes memory) {
        return abi.encode(version_, currency_, tickLower_, tickUpper_, numDiscoveryPositions_, maxDiscoverySupplyShare_);
    }
}
