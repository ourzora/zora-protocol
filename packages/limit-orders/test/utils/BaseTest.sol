// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Vm} from "forge-std/Vm.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {V4TestSetup} from "@zoralabs/coins/test/utils/V4TestSetup.sol";
import {IZoraLimitOrderBook} from "../../src/IZoraLimitOrderBook.sol";
import {TestableZoraLimitOrderBook} from "./TestableZoraLimitOrderBook.sol";
import {SwapWithLimitOrders} from "../../src/router/SwapWithLimitOrders.sol";
import {IMsgSender} from "@zoralabs/coins/src/interfaces/IMsgSender.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {CreatorCoin} from "@zoralabs/coins/src/CreatorCoin.sol";
import {ContentCoin} from "@zoralabs/coins/src/ContentCoin.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {LimitOrderConfig} from "../../src/libs/SwapLimitOrders.sol";
import {CoinConfigurationVersions} from "@zoralabs/coins/src/libs/CoinConfigurationVersions.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {UniV4SwapHelper} from "@zoralabs/coins/src/libs/UniV4SwapHelper.sol";
import {LimitOrderCommon} from "../../src/libs/LimitOrderCommon.sol";
import {LimitOrderStorage} from "../../src/libs/LimitOrderStorage.sol";
import {LimitOrderTypes} from "../../src/libs/LimitOrderTypes.sol";
import {TickBitmap} from "@uniswap/v4-core/src/libraries/TickBitmap.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {AddressConstants} from "@zoralabs/coins/test/utils/hookmate/constants/AddressConstants.sol";
import {ICoin} from "@zoralabs/coins/src/interfaces/ICoin.sol";

/**
 * @title BaseTest
 * @notice Limit-orders-specific test utilities extending V4TestSetup
 * @dev This contract adds limit-order-specific setup on top of shared V4 infrastructure
 */
contract BaseTest is V4TestSetup, IMsgSender {
    using PoolIdLibrary for PoolKey;
    TestableZoraLimitOrderBook internal limitOrderBook = TestableZoraLimitOrderBook(payable(makeAddr("limitOrderBook")));
    AccessManager internal accessManager;
    SwapWithLimitOrders internal swapWithLimitOrders;

    function setUp() public virtual {
        setUpNonForked();
    }

    function setUpWithBlockNumber(uint256 forkBlockNumber) public virtual {
        // First set up limit order book (needs to be done before _setUpWithBlockNumber which calls _deployHooks)
        _setUpWithBlockNumber(forkBlockNumber, address(limitOrderBook));
        _setupLimitOrderBook();
    }

    function setUpNonForked() public virtual {
        // For non-forked tests, use a mock that doesn't access transient storage
        // since the pool manager doesn't have the same transient state as in fork tests
        // mockLimitOrderBookForHook = new MockZoraLimitOrderBookNoTransientStorage();
        _setUpNonForked(address(limitOrderBook));
        _setupLimitOrderBook();
    }

    function _setupLimitOrderBook() internal {
        // Deploy AccessManager with this contract as admin
        accessManager = new AccessManager(address(this));

        deployCodeTo(
            "TestableZoraLimitOrderBook.sol:TestableZoraLimitOrderBook",
            abi.encode(address(poolManager), address(factory), address(zoraHookRegistry), address(accessManager)),
            address(limitOrderBook)
        );
        require(limitOrderBook.authority() == address(accessManager), "ZoraLimitOrderBook authority is not the access manager");

        // Set create() and setMaxFillCount() functions to PUBLIC_ROLE to allow anyone to call them initially
        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = IZoraLimitOrderBook.create.selector;
        selectors[1] = IZoraLimitOrderBook.setMaxFillCount.selector;
        accessManager.setTargetFunctionRole(address(limitOrderBook), selectors, accessManager.PUBLIC_ROLE());

        limitOrderBook.setMaxFillCount(50);

        vm.label(address(limitOrderBook), "LIMIT_ORDER_BOOK");

        swapWithLimitOrders = new SwapWithLimitOrders(poolManager, limitOrderBook, swapRouter, AddressConstants.getPermit2Address());
        vm.label(address(swapWithLimitOrders), "SWAP_WITH_LIMIT_ORDERS");
        // Now create the real ZoraLimitOrderBook for tests that need it
        _deployTestCoins();
    }

    function _getLimitOrderBookAddress() internal view virtual override returns (address) {
        return address(limitOrderBook);
    }

    // Alias for compatibility with test suite
    uint256 internal constant DEFAULT_LIMIT_ORDER_FILL_COUNT = 50;
    uint256 internal constant DEFAULT_LIMIT_ORDER_AMOUNT = 100e18;

    bytes32 internal constant LIMIT_ORDER_CREATED_TOPIC = keccak256("LimitOrderCreated(address,address,bytes32,bool,int24,int24,uint128,bytes32)");
    bytes32 internal constant LIMIT_ORDER_FILLED_TOPIC =
        keccak256("LimitOrderFilled(address,address,address,uint128,uint128,address,uint128,bytes32,int24,bytes32)");
    bytes32 internal constant LIMIT_ORDER_UPDATED_TOPIC = keccak256("LimitOrderUpdated(address,address,bytes32,bool,int24,uint128,bytes32,bool)");
    bytes32 internal constant SWAP_WITH_LIMIT_ORDERS_EXECUTED_TOPIC =
        keccak256(
            "SwapWithLimitOrdersExecuted(address,address,(address,address,uint24,int24,address),int24,int24,int128,int128,uint160,(bytes32,uint256,uint256)[])"
        );

    struct QueueSnapshot {
        bytes32 head;
        bytes32 tail;
        uint128 length;
        uint128 balance;
    }

    struct CreatedOrderLog {
        address maker;
        address coin;
        bytes32 poolKeyHash;
        bool isCurrency0;
        int24 tick;
        int24 currentTick;
        uint128 size;
        bytes32 orderId;
    }

    struct FilledOrderLog {
        address maker;
        address coinIn;
        address coinOut;
        uint128 amountIn;
        uint128 amountOut;
        address fillReferral;
        uint128 fillReferralAmount;
        bytes32 poolKeyHash;
        int24 tick;
        bytes32 orderId;
    }

    struct UpdatedOrderLog {
        address maker;
        address coin;
        bytes32 poolKeyHash;
        bool isCurrency0;
        int24 tick;
        uint128 newSize;
        bytes32 orderId;
        bool isCancelled;
    }

    struct CreatedOrder {
        bytes32 orderId;
        uint256 multiple;
        uint256 percentage;
    }

    struct SwapExecutedLog {
        address sender;
        address recipient;
        PoolKey poolKey;
        int24 tickBefore;
        int24 tickAfter;
        int128 amount0;
        int128 amount1;
        uint160 sqrtPriceX96;
        CreatedOrder[] orders;
    }

    address internal routerMsgSender;
    CreatorCoin internal creatorCoin;
    ContentCoin internal contentCoin;

    function msgSender() external view override returns (address) {
        return routerMsgSender;
    }

    function _setRouterMsgSender(address newSender) internal {
        routerMsgSender = newSender;
    }

    function _deployTestCoins() internal {
        creatorCoin = _deployCreatorCoin();
        contentCoin = _deployContentCoin(address(creatorCoin));
    }

    function _deployCreatorCoin() internal returns (CreatorCoin deployed) {
        bytes memory poolConfig = _creatorCoinPoolConfig();

        vm.prank(users.creator);
        address coinAddress = factory.deployCreatorCoin(
            users.creator,
            _getDefaultOwners(),
            "https://testcreatorcoin.com",
            "TestCreatorCoin",
            "TESTCREATORCOIN",
            poolConfig,
            address(0),
            bytes32(0)
        );

        deployed = CreatorCoin(coinAddress);
        vm.label(coinAddress, "TEST_CREATOR_COIN");
    }

    function _deployContentCoin(address currency) internal returns (ContentCoin deployed) {
        bytes memory poolConfig = _contentCoinPoolConfig(currency);

        vm.prank(users.creator);
        (address coinAddress, ) = factory.deploy(
            users.creator,
            _getDefaultOwners(),
            "https://testcontentcoin.com",
            "TestContentCoin",
            "TESTCONTENTCOIN",
            poolConfig,
            address(0),
            address(0),
            bytes(""),
            bytes32(0)
        );

        deployed = ContentCoin(coinAddress);
        vm.label(coinAddress, "TEST_CONTENT_COIN");
    }

    function _creatorCoinPoolConfig() internal view returns (bytes memory) {
        int24[] memory tickLower = new int24[](3);
        int24[] memory tickUpper = new int24[](3);
        uint16[] memory numDiscoveryPositions = new uint16[](3);
        uint256[] memory maxDiscoverySupplyShare = new uint256[](3);

        tickLower[0] = -103_000;
        tickUpper[0] = -74_000;
        numDiscoveryPositions[0] = 11;
        maxDiscoverySupplyShare[0] = 0.075e18;

        tickLower[1] = -88_000;
        tickUpper[1] = -66_000;
        numDiscoveryPositions[1] = 11;
        maxDiscoverySupplyShare[1] = 0.125e18;

        tickLower[2] = -76_000;
        tickUpper[2] = -66_000;
        numDiscoveryPositions[2] = 11;
        maxDiscoverySupplyShare[2] = 0.175e18;

        return
            abi.encode(
                CoinConfigurationVersions.DOPPLER_MULTICURVE_UNI_V4_POOL_VERSION,
                address(zoraToken),
                tickLower,
                tickUpper,
                numDiscoveryPositions,
                maxDiscoverySupplyShare
            );
    }

    function _contentCoinPoolConfig(address currency) internal pure returns (bytes memory) {
        int24[] memory tickLower = new int24[](4);
        int24[] memory tickUpper = new int24[](4);
        uint16[] memory numDiscoveryPositions = new uint16[](4);
        uint256[] memory maxDiscoverySupplyShare = new uint256[](4);

        tickLower[0] = -54_000;
        tickUpper[0] = -7000;
        numDiscoveryPositions[0] = 11;
        maxDiscoverySupplyShare[0] = 0.1e18;

        tickLower[1] = -30_000;
        tickUpper[1] = 7000;
        numDiscoveryPositions[1] = 11;
        maxDiscoverySupplyShare[1] = 0.2e18;

        tickLower[2] = -39_000;
        tickUpper[2] = 7000;
        numDiscoveryPositions[2] = 11;
        maxDiscoverySupplyShare[2] = 0.1e18;

        tickLower[3] = -85_000;
        tickUpper[3] = 7000;
        numDiscoveryPositions[3] = 11;
        maxDiscoverySupplyShare[3] = 0.05e18;

        return
            abi.encode(
                CoinConfigurationVersions.DOPPLER_MULTICURVE_UNI_V4_POOL_VERSION,
                currency,
                tickLower,
                tickUpper,
                numDiscoveryPositions,
                maxDiscoverySupplyShare
            );
    }

    function _defaultMultiples() internal pure returns (uint256[] memory multiples) {
        multiples = new uint256[](5);
        multiples[0] = 2e18;
        multiples[1] = 4e18;
        multiples[2] = 8e18;
        multiples[3] = 16e18;
        multiples[4] = 32e18;
    }

    function _defaultPercentages() internal pure returns (uint256[] memory percentages) {
        percentages = new uint256[](5);
        percentages[0] = 2000; // 20%
        percentages[1] = 2000; // 20%
        percentages[2] = 2000; // 20%
        percentages[3] = 2000; // 20%
        percentages[4] = 2000; // 20%
    }

    function _prepareLimitOrderParams(
        address, // maker - unused, kept for compatibility
        uint256[] memory multiples,
        uint256[] memory percentages
    ) internal pure returns (LimitOrderConfig memory params) {
        params.multiples = multiples;
        params.percentages = percentages;
    }

    function _executeSingleHopSwapWithLimitOrders(
        address trader,
        PoolKey memory poolKey,
        uint256 amountIn,
        uint256[] memory multiples,
        uint256[] memory percentages
    ) internal returns (LimitOrderConfig memory params) {
        params = _prepareLimitOrderParams(trader, multiples, percentages);

        // Use SwapWithLimitOrders router to create autosell orders
        PoolKey[] memory route = new PoolKey[](1);
        route[0] = poolKey;
        _executeSwapWithLimitOrders(trader, amountIn, route, params);
    }

    function _executeMultiHopSwapWithLimitOrders(
        address trader,
        PoolKey[] memory keys,
        uint256 amountIn,
        uint256[] memory multiples,
        uint256[] memory percentages
    ) internal returns (LimitOrderConfig memory params) {
        params = _prepareLimitOrderParams(trader, multiples, percentages);

        // Use SwapWithLimitOrders router to create autosell orders
        _executeSwapWithLimitOrders(trader, amountIn, keys, params);
    }

    function _executeSwapWithLimitOrders(address trader, uint256 amountIn, PoolKey[] memory keys, LimitOrderConfig memory params) internal {
        deal(address(zoraToken), trader, amountIn);

        vm.startPrank(trader);
        // Approve Permit2 to spend tokens (matching universal-router pattern)
        address permit2 = AddressConstants.getPermit2Address();
        IERC20(address(zoraToken)).approve(permit2, type(uint256).max);

        // Approve swapWithLimitOrders as spender in Permit2
        // Use uint48 max for expiration to never expire during tests
        IAllowanceTransfer(permit2).approve(address(zoraToken), address(swapWithLimitOrders), uint160(type(uint160).max), type(uint48).max);

        SwapWithLimitOrders.SwapWithLimitOrdersParams memory swapParams = SwapWithLimitOrders.SwapWithLimitOrdersParams({
            recipient: trader,
            limitOrderConfig: params,
            inputCurrency: address(zoraToken),
            inputAmount: amountIn,
            v3Route: bytes(""),
            v4Route: keys,
            minAmountOut: 0
        });

        swapWithLimitOrders.swapWithLimitOrders(swapParams);
        vm.stopPrank();
    }

    function _executeSingleHopSwap(address trader, uint256 amountIn, PoolKey memory poolKey, bytes memory hookData) internal {
        deal(address(zoraToken), trader, amountIn);

        address currencyOut = Currency.unwrap(poolKey.currency0) == address(zoraToken)
            ? Currency.unwrap(poolKey.currency1)
            : Currency.unwrap(poolKey.currency0);

        (bytes memory commands, bytes[] memory inputs) = UniV4SwapHelper.buildExactInputSingleSwapCommand(
            address(zoraToken),
            uint128(amountIn),
            currencyOut,
            0,
            poolKey,
            hookData
        );

        vm.startPrank(trader);
        UniV4SwapHelper.approveTokenWithPermit2(permit2, address(router), address(zoraToken), uint128(amountIn), uint48(block.timestamp + 1 days));
        router.execute(commands, inputs, block.timestamp + 1 days);
        vm.stopPrank();
    }

    function _executeMultiHopSwap(address trader, uint256 amountIn, PoolKey[] memory poolKeys, bytes[] memory hookDatas) internal {
        deal(address(zoraToken), trader, amountIn);

        (bytes memory commands, bytes[] memory inputs) = UniV4SwapHelper.buildExactInputMultiSwapCommand(
            address(zoraToken),
            uint128(amountIn),
            poolKeys,
            0,
            hookDatas
        );

        vm.startPrank(trader);
        UniV4SwapHelper.approveTokenWithPermit2(permit2, address(router), address(zoraToken), uint128(amountIn), uint48(block.timestamp + 1 days));
        router.execute(commands, inputs, block.timestamp + 1 days);
        vm.stopPrank();
    }

    function _makerNonce(address maker) internal view returns (uint256) {
        return limitOrderBook.exposedMakerNonce(maker);
    }

    function _makerBalance(address maker, address coin) internal view returns (uint256) {
        return limitOrderBook.balanceOf(maker, coin);
    }

    function _poolEpoch(bytes32 poolKeyHash) internal view returns (uint256) {
        return limitOrderBook.exposedPoolEpoch(poolKeyHash);
    }

    function _orderIds(CreatedOrderLog[] memory created) internal pure returns (bytes32[] memory ids) {
        ids = new bytes32[](created.length);
        for (uint256 i; i < created.length; ++i) {
            ids[i] = created[i].orderId;
        }
    }

    function _sumOrderSizes(CreatedOrderLog[] memory created) internal pure returns (uint256 total) {
        for (uint256 i; i < created.length; ++i) {
            total += created[i].size;
        }
    }

    function _orderCoin(PoolKey memory key, bool isCurrency0) internal pure returns (address) {
        return LimitOrderCommon.getOrderCoin(key, isCurrency0);
    }

    function _assertEpochIncrement(bytes32 poolKeyHash, uint256 previousEpoch) internal view {
        uint256 current = _poolEpoch(poolKeyHash);
        assertGt(current, previousEpoch, "pool epoch should increment after fills");
    }

    function _tickWindow(CreatedOrderLog[] memory created, PoolKey memory key) internal pure returns (int24 startTick, int24 endTick) {
        if (created.length == 0) {
            return (0, 0);
        }

        int24 minTick = created[0].tick;
        int24 maxTick = created[0].tick;
        for (uint256 i = 1; i < created.length; ++i) {
            if (created[i].tick < minTick) minTick = created[i].tick;
            if (created[i].tick > maxTick) maxTick = created[i].tick;
        }

        if (created[0].isCurrency0) {
            startTick = minTick - key.tickSpacing;
            endTick = maxTick + key.tickSpacing;
        } else {
            startTick = maxTick + key.tickSpacing;
            endTick = minTick - key.tickSpacing;
        }
    }

    function _alignedTickForOrder(bool isCurrency0, int24 baseTick, int24 spacing, uint256 index) internal pure returns (int24) {
        int24 offset = int24(int256(spacing) * int256(index + 1));
        // For currency0 sell orders: place above current (contain currency0)
        // For currency1 sell orders: place below current (contain currency1)
        return isCurrency0 ? baseTick + offset : baseTick - offset;
    }

    function _buildDeterministicOrders(
        PoolKey memory key,
        bool isCurrency0,
        uint256 rungCount,
        uint256 orderSize
    ) internal view returns (uint256[] memory sizes, int24[] memory ticks) {
        sizes = new uint256[](rungCount);
        ticks = new int24[](rungCount);

        int24 baseTick = _alignedTick(_currentTick(key), key.tickSpacing);
        for (uint256 i; i < rungCount; ++i) {
            sizes[i] = orderSize;
            ticks[i] = _alignedTickForOrder(isCurrency0, baseTick, key.tickSpacing, i);
        }
    }

    function _assertOpenOrderState(address, address coin, bytes32 poolKeyHash, CreatedOrderLog[] memory orders, int24 tickSpacing) internal view {
        uint256 orderCount = orders.length;

        for (uint256 i; i < orderCount; ++i) {
            bool seen;
            for (uint256 j; j < i; ++j) {
                if (orders[j].coin == orders[i].coin && orders[j].tick == orders[i].tick) {
                    seen = true;
                    break;
                }
            }
            if (seen) continue;

            uint256 tickCount;
            uint256 tickSize;
            for (uint256 k = i; k < orderCount; ++k) {
                if (orders[k].coin == orders[i].coin && orders[k].tick == orders[i].tick) {
                    ++tickCount;
                    tickSize += orders[k].size;
                }
            }

            QueueSnapshot memory tickQueue = _tickQueueSnapshot(poolKeyHash, coin, orders[i].tick);
            assertEq(uint256(tickQueue.length), tickCount, "tick queue length mismatch");
            assertEq(uint256(tickQueue.balance), tickSize, "tick queue balance mismatch");
            assertTrue(_isTickInitialized(poolKeyHash, coin, orders[i].tick, tickSpacing), "tick bitmap missing");
        }
    }

    function _setOrderCreatedEpoch(bytes32 orderId, uint32 newEpoch) internal {
        bytes32 layoutSlot = LimitOrderStorage.STORAGE_SLOT;
        bytes32 limitOrdersSlot = keccak256(abi.encode(uint256(0), layoutSlot));
        bytes32 orderSlot = keccak256(abi.encode(orderId, limitOrdersSlot));
        bytes32 metaSlot = bytes32(uint256(orderSlot) + 4); // Slot 4 contains packed metadata (tickLower, tickUpper, createdEpoch, status, isCurrency0, maker)

        uint256 slotValue = uint256(vm.load(address(limitOrderBook), metaSlot));
        uint256 mask = ~(uint256(0xffffffff) << 48);
        slotValue = (slotValue & mask) | (uint256(newEpoch) << 48);
        vm.store(address(limitOrderBook), metaSlot, bytes32(slotValue));
    }

    function _tickQueueSnapshot(bytes32 poolKeyHash, address coin, int24 tick) internal view returns (QueueSnapshot memory snapshot) {
        LimitOrderTypes.Queue memory queue = limitOrderBook.exposedTickQueue(poolKeyHash, coin, tick);
        snapshot.head = queue.head;
        snapshot.tail = queue.tail;
        snapshot.length = queue.length;
        snapshot.balance = queue.balance;
    }

    function _bitmapWord(bytes32 poolKeyHash, address coin, int16 wordPos) internal view returns (uint256) {
        return limitOrderBook.exposedTickBitmap(poolKeyHash, coin, wordPos);
    }

    function _topicAddress(bytes32 topic) internal pure returns (address) {
        return address(uint160(uint256(topic)));
    }

    function _isTickInitialized(bytes32 poolKeyHash, address coin, int24 tick, int24 tickSpacing) internal view returns (bool) {
        int24 compressed = tick / tickSpacing;
        (int16 wordPos, uint8 bitPos) = TickBitmap.position(compressed);
        uint256 word = _bitmapWord(poolKeyHash, coin, wordPos);
        return (word & (1 << bitPos)) != 0;
    }

    function _decodeCreatedLogs(Vm.Log[] memory logs) internal pure returns (CreatedOrderLog[] memory created) {
        uint256 count;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length == 0) continue;
            if (logs[i].topics[0] != LIMIT_ORDER_CREATED_TOPIC) continue;
            ++count;
        }

        created = new CreatedOrderLog[](count);
        uint256 idx;
        for (uint256 i; i < logs.length; ++i) {
            Vm.Log memory log = logs[i];
            if (log.topics.length == 0 || log.topics[0] != LIMIT_ORDER_CREATED_TOPIC) continue;

            (bytes32 poolKeyHash, bool isCurrency0, int24 tick, int24 currentTick, uint128 size, bytes32 orderId) = abi.decode(
                log.data,
                (bytes32, bool, int24, int24, uint128, bytes32)
            );

            CreatedOrderLog memory entry;
            entry.maker = _topicAddress(log.topics[1]);
            entry.coin = _topicAddress(log.topics[2]);
            entry.poolKeyHash = poolKeyHash;
            entry.isCurrency0 = isCurrency0;
            entry.tick = tick;
            entry.currentTick = currentTick;
            entry.size = size;
            entry.orderId = orderId;

            created[idx] = entry;
            ++idx;
        }
    }

    function _decodeFilledLogs(Vm.Log[] memory logs) internal pure returns (FilledOrderLog[] memory fills) {
        uint256 count;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length == 0) continue;
            if (logs[i].topics[0] != LIMIT_ORDER_FILLED_TOPIC) continue;
            ++count;
        }

        fills = new FilledOrderLog[](count);
        uint256 idx;
        for (uint256 i; i < logs.length; ++i) {
            Vm.Log memory log = logs[i];
            if (log.topics.length == 0 || log.topics[0] != LIMIT_ORDER_FILLED_TOPIC) continue;

            (
                address coinOut,
                uint128 amountIn,
                uint128 amountOut,
                address fillReferral,
                uint128 fillReferralAmount,
                bytes32 poolKeyHash,
                int24 tick,
                bytes32 orderId
            ) = abi.decode(log.data, (address, uint128, uint128, address, uint128, bytes32, int24, bytes32));

            FilledOrderLog memory entry;
            entry.maker = _topicAddress(log.topics[1]);
            entry.coinIn = _topicAddress(log.topics[2]);
            entry.coinOut = coinOut;
            entry.amountIn = amountIn;
            entry.amountOut = amountOut;
            entry.fillReferral = fillReferral;
            entry.fillReferralAmount = fillReferralAmount;
            entry.poolKeyHash = poolKeyHash;
            entry.tick = tick;
            entry.orderId = orderId;

            fills[idx] = entry;
            ++idx;
        }
    }

    function _decodeUpdatedLogs(Vm.Log[] memory logs) internal pure returns (UpdatedOrderLog[] memory updates) {
        uint256 count;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length == 0) continue;
            if (logs[i].topics[0] != LIMIT_ORDER_UPDATED_TOPIC) continue;
            ++count;
        }

        updates = new UpdatedOrderLog[](count);
        uint256 idx;
        for (uint256 i; i < logs.length; ++i) {
            Vm.Log memory log = logs[i];
            if (log.topics.length == 0 || log.topics[0] != LIMIT_ORDER_UPDATED_TOPIC) continue;

            (bytes32 poolKeyHash, bool isCurrency0, int24 tick, uint128 newSize, bytes32 orderId, bool isCancelled) = abi.decode(
                log.data,
                (bytes32, bool, int24, uint128, bytes32, bool)
            );

            updates[idx] = UpdatedOrderLog({
                maker: address(uint160(uint256(log.topics[1]))),
                coin: address(uint160(uint256(log.topics[2]))),
                poolKeyHash: poolKeyHash,
                isCurrency0: isCurrency0,
                tick: tick,
                newSize: newSize,
                orderId: orderId,
                isCancelled: isCancelled
            });
            ++idx;
        }
    }

    function _decodeSwapExecutedLogs(Vm.Log[] memory logs) internal pure returns (SwapExecutedLog[] memory swaps) {
        uint256 count;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length == 0) continue;
            if (logs[i].topics[0] != SWAP_WITH_LIMIT_ORDERS_EXECUTED_TOPIC) continue;
            ++count;
        }

        swaps = new SwapExecutedLog[](count);
        uint256 idx;
        for (uint256 i; i < logs.length; ++i) {
            Vm.Log memory log = logs[i];
            if (log.topics.length == 0 || log.topics[0] != SWAP_WITH_LIMIT_ORDERS_EXECUTED_TOPIC) continue;

            (
                PoolKey memory poolKey,
                int24 tickBefore,
                int24 tickAfter,
                int128 amount0,
                int128 amount1,
                uint160 sqrtPriceX96,
                CreatedOrder[] memory orders
            ) = abi.decode(log.data, (PoolKey, int24, int24, int128, int128, uint160, CreatedOrder[]));

            swaps[idx] = SwapExecutedLog({
                sender: address(uint160(uint256(log.topics[1]))),
                recipient: address(uint160(uint256(log.topics[2]))),
                poolKey: poolKey,
                tickBefore: tickBefore,
                tickAfter: tickAfter,
                amount0: amount0,
                amount1: amount1,
                sqrtPriceX96: sqrtPriceX96,
                orders: orders
            });
            ++idx;
        }
    }

    function _setPoolTick(PoolKey memory key, int24 newTick) internal {
        bytes32 poolId = PoolId.unwrap(key.toId());
        bytes32 slot0Slot = keccak256(abi.encodePacked(poolId, StateLibrary.POOLS_SLOT));
        bytes32 slot0Value = vm.load(address(poolManager), slot0Slot);
        uint256 data = uint256(slot0Value);

        uint256 protocolFee = (data >> 184) & 0xFFFFFF;
        uint256 lpFee = (data >> 208) & 0xFFFFFF;
        uint256 upperBits = data & ~((uint256(1) << 232) - 1);

        uint256 tickBits;
        assembly {
            tickBits := and(newTick, 0xffffff)
        }

        uint160 sqrtPriceX96 = TickMath.getSqrtPriceAtTick(newTick);

        uint256 newData = upperBits;
        newData |= uint256(sqrtPriceX96);
        newData |= tickBits << 160;
        newData |= protocolFee << 184;
        newData |= lpFee << 208;

        vm.store(address(poolManager), slot0Slot, bytes32(newData));
    }

    function _fillFromHook(PoolKey memory key, bool zeroForOne, int24 tickBefore, int24 tickAfter) internal {
        vm.prank(address(hook));
        limitOrderBook.fill(key, !zeroForOne, tickBefore, tickAfter, 10, address(0));
    }

    function _approveOrderBook(address owner, address coin, uint256 amount) internal {
        vm.startPrank(owner);
        if (coin != address(0)) {
            IERC20(coin).approve(address(limitOrderBook), amount);
        }
        vm.stopPrank();
    }

    function _currentTick(PoolKey memory key) internal view returns (int24 tick) {
        (, tick, , ) = StateLibrary.getSlot0(poolManager, key.toId());
    }

    function _alignedTick(int24 tick, int24 spacing) internal pure returns (int24) {
        int24 remainder = tick % spacing;
        if (remainder == 0) return tick;
        if (tick >= 0) {
            return tick - remainder;
        } else {
            return tick - (spacing + remainder);
        }
    }

    function _movePriceBeyondTicks(CreatedOrderLog[] memory created) internal virtual {
        if (created.length == 0) return;

        address mover = makeAddr("price-mover");
        // Pool has significant liquidity, need large swap to move tick past all orders
        uint256 swapAmount = 50_000_000e18;

        // Check if coin is currency0 or currency1 in the pool
        PoolKey memory key = creatorCoin.getPoolKey();
        bool coinIsCurrency0 = Currency.unwrap(key.currency0) == address(creatorCoin);
        bool isCurrency0Order = created[0].isCurrency0;

        // For currency0 orders: need tick UP (currentTick >= tickUpper)
        // For currency1 orders: need tick DOWN (currentTick <= tickLower)
        //
        // When coin is currency1 (token1):
        //   - Sell coin → tick increases (add token1, price of token0 rises)
        //   - Buy coin → tick decreases
        // When coin is currency0 (token0):
        //   - Sell coin → tick decreases (add token0, price of token0 drops)
        //   - Buy coin → tick increases

        bool needTickUp = isCurrency0Order;
        bool sellCoinIncreaseTick = !coinIsCurrency0; // selling token1 increases tick

        if (needTickUp == sellCoinIncreaseTick) {
            // Sell coin to move tick in required direction
            deal(address(creatorCoin), mover, swapAmount);
            _swapSomeCoinForCurrency(ICoin(address(creatorCoin)), address(zoraToken), uint128(swapAmount), mover);
        } else {
            // Buy coin to move tick in required direction
            deal(address(zoraToken), mover, swapAmount);
            _swapSomeCurrencyForCoin(ICoin(address(creatorCoin)), address(zoraToken), uint128(swapAmount), mover);
        }
    }

    function _movePriceBeyondTicksWithAutoFillDisabled(CreatedOrderLog[] memory created) internal virtual {
        uint256 previousMax = _disableAutoFill();
        _movePriceBeyondTicks(created);
        _restoreAutoFill(previousMax);
    }

    function _disableAutoFill() internal returns (uint256 previousMaxFillCount) {
        previousMaxFillCount = limitOrderBook.getMaxFillCount();
        vm.prank(users.factoryOwner);
        limitOrderBook.setMaxFillCount(0);
    }

    function _restoreAutoFill(uint256 previousMaxFillCount) internal {
        vm.prank(users.factoryOwner);
        limitOrderBook.setMaxFillCount(previousMaxFillCount);
    }
}
