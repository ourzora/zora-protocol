// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {BaseTest} from "./utils/BaseTest.sol";
import {LimitOrderQueues} from "../src/libs/LimitOrderQueues.sol";
import {LimitOrderTypes} from "../src/libs/LimitOrderTypes.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";

contract LimitOrderLibrariesTest is BaseTest {
    using LimitOrderQueues for LimitOrderTypes.Queue;
    using PoolIdLibrary for PoolKey;

    function test_enqueueIntoEmptyQueue() public {
        PoolKey memory key = creatorCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(key.currency0) == address(creatorCoin);
        address orderCoin = _orderCoin(key, isCurrency0);

        // Create single order to test empty queue enqueue
        (uint256[] memory orderSizes, int24[] memory orderTicks) = _buildDeterministicOrders(key, isCurrency0, 1, 25e18);

        _fundAndApprove(users.seller, orderCoin, orderSizes[0]);

        vm.recordLogs();
        vm.prank(users.seller);
        limitOrderBook.create{value: orderCoin == address(0) ? orderSizes[0] : 0}(key, isCurrency0, orderSizes, orderTicks, users.seller);

        CreatedOrderLog[] memory created = _decodeCreatedLogs(vm.getRecordedLogs());
        assertEq(created.length, 1, "should create one order");

        // Verify tick queue state after enqueue into empty queue
        QueueSnapshot memory tickQueue = _tickQueueSnapshot(created[0].poolKeyHash, orderCoin, created[0].tick);
        assertEq(tickQueue.length, 1, "queue length should be 1");
        assertEq(tickQueue.head, created[0].orderId, "head should be the order");
        assertEq(tickQueue.tail, created[0].orderId, "tail should be the order");
    }

    function test_enqueueIntoNonEmptyQueue() public {
        PoolKey memory key = creatorCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(key.currency0) == address(creatorCoin);
        address orderCoin = _orderCoin(key, isCurrency0);

        // Create multiple orders at the same tick to test non-empty queue enqueue
        int24 tick = _getValidTick(key, isCurrency0);
        uint256[] memory orderSizes = new uint256[](3);
        orderSizes[0] = 25e18;
        orderSizes[1] = 25e18;
        orderSizes[2] = 25e18;
        int24[] memory orderTicks = new int24[](3);
        orderTicks[0] = tick;
        orderTicks[1] = tick;
        orderTicks[2] = tick;

        uint256 totalSize;
        for (uint256 i; i < orderSizes.length; ++i) {
            totalSize += orderSizes[i];
        }
        _fundAndApprove(users.seller, orderCoin, totalSize);

        vm.recordLogs();
        vm.prank(users.seller);
        limitOrderBook.create{value: orderCoin == address(0) ? totalSize : 0}(key, isCurrency0, orderSizes, orderTicks, users.seller);

        CreatedOrderLog[] memory created = _decodeCreatedLogs(vm.getRecordedLogs());
        assertEq(created.length, 3, "should create three orders");

        // Verify tick queue linked list structure
        int24 fillableTick = _fillableTick(isCurrency0, tick, key.tickSpacing);
        QueueSnapshot memory tickQueue = _tickQueueSnapshot(created[0].poolKeyHash, orderCoin, fillableTick);
        assertEq(tickQueue.length, 3, "queue length should be 3");
        assertEq(tickQueue.head, created[0].orderId, "head should be first order");
        assertEq(tickQueue.tail, created[2].orderId, "tail should be last order");
    }

    function test_unlinkHead() public {
        PoolKey memory key = creatorCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(key.currency0) == address(creatorCoin);
        address orderCoin = _orderCoin(key, isCurrency0);

        // Create 3 orders at the same tick to test unlink head
        int24 tick = _getValidTick(key, isCurrency0);
        uint256[] memory orderSizes = new uint256[](3);
        orderSizes[0] = 25e18;
        orderSizes[1] = 25e18;
        orderSizes[2] = 25e18;
        int24[] memory orderTicks = new int24[](3);
        orderTicks[0] = tick;
        orderTicks[1] = tick;
        orderTicks[2] = tick;

        uint256 totalSize;
        for (uint256 i; i < orderSizes.length; ++i) {
            totalSize += orderSizes[i];
        }
        _fundAndApprove(users.seller, orderCoin, totalSize);

        vm.recordLogs();
        vm.prank(users.seller);
        limitOrderBook.create{value: orderCoin == address(0) ? totalSize : 0}(key, isCurrency0, orderSizes, orderTicks, users.seller);

        CreatedOrderLog[] memory created = _decodeCreatedLogs(vm.getRecordedLogs());
        bytes32 headId = created[0].orderId;

        // Withdraw head order
        bytes32[] memory orderIds = new bytes32[](1);
        orderIds[0] = headId;
        vm.prank(users.seller);
        limitOrderBook.withdraw(orderIds, orderCoin, 0, users.seller);

        int24 fillableTick = _fillableTick(isCurrency0, tick, key.tickSpacing);
        QueueSnapshot memory tickQueue = _tickQueueSnapshot(created[0].poolKeyHash, orderCoin, fillableTick);
        assertEq(tickQueue.length, 2, "queue length should be 2");
        assertEq(tickQueue.head, created[1].orderId, "head should be second order");
        assertEq(tickQueue.tail, created[2].orderId, "tail unchanged");
    }

    function test_unlinkTail() public {
        PoolKey memory key = creatorCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(key.currency0) == address(creatorCoin);
        address orderCoin = _orderCoin(key, isCurrency0);

        // Create 3 orders at the same tick to test unlink tail
        int24 tick = _getValidTick(key, isCurrency0);
        uint256[] memory orderSizes = new uint256[](3);
        orderSizes[0] = 25e18;
        orderSizes[1] = 25e18;
        orderSizes[2] = 25e18;
        int24[] memory orderTicks = new int24[](3);
        orderTicks[0] = tick;
        orderTicks[1] = tick;
        orderTicks[2] = tick;

        uint256 totalSize;
        for (uint256 i; i < orderSizes.length; ++i) {
            totalSize += orderSizes[i];
        }
        _fundAndApprove(users.seller, orderCoin, totalSize);

        vm.recordLogs();
        vm.prank(users.seller);
        limitOrderBook.create{value: orderCoin == address(0) ? totalSize : 0}(key, isCurrency0, orderSizes, orderTicks, users.seller);

        CreatedOrderLog[] memory created = _decodeCreatedLogs(vm.getRecordedLogs());
        bytes32 tailId = created[2].orderId;

        // Withdraw tail order
        bytes32[] memory orderIds = new bytes32[](1);
        orderIds[0] = tailId;
        vm.prank(users.seller);
        limitOrderBook.withdraw(orderIds, orderCoin, 0, users.seller);

        int24 fillableTick = _fillableTick(isCurrency0, tick, key.tickSpacing);
        QueueSnapshot memory tickQueue = _tickQueueSnapshot(created[0].poolKeyHash, orderCoin, fillableTick);
        assertEq(tickQueue.length, 2, "queue length should be 2");
        assertEq(tickQueue.head, created[0].orderId, "head unchanged");
        assertEq(tickQueue.tail, created[1].orderId, "tail should be second order");
    }

    function test_unlinkMiddle() public {
        PoolKey memory key = creatorCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(key.currency0) == address(creatorCoin);
        address orderCoin = _orderCoin(key, isCurrency0);

        // Create 3 orders at the same tick to test unlink middle
        int24 tick = _getValidTick(key, isCurrency0);
        uint256[] memory orderSizes = new uint256[](3);
        orderSizes[0] = 25e18;
        orderSizes[1] = 25e18;
        orderSizes[2] = 25e18;
        int24[] memory orderTicks = new int24[](3);
        orderTicks[0] = tick;
        orderTicks[1] = tick;
        orderTicks[2] = tick;

        uint256 totalSize;
        for (uint256 i; i < orderSizes.length; ++i) {
            totalSize += orderSizes[i];
        }
        _fundAndApprove(users.seller, orderCoin, totalSize);

        vm.recordLogs();
        vm.prank(users.seller);
        limitOrderBook.create{value: orderCoin == address(0) ? totalSize : 0}(key, isCurrency0, orderSizes, orderTicks, users.seller);

        CreatedOrderLog[] memory created = _decodeCreatedLogs(vm.getRecordedLogs());
        bytes32 middleId = created[1].orderId;

        // Withdraw middle order
        bytes32[] memory orderIds = new bytes32[](1);
        orderIds[0] = middleId;
        vm.prank(users.seller);
        limitOrderBook.withdraw(orderIds, orderCoin, 0, users.seller);

        int24 fillableTick = _fillableTick(isCurrency0, tick, key.tickSpacing);
        QueueSnapshot memory tickQueue = _tickQueueSnapshot(created[0].poolKeyHash, orderCoin, fillableTick);
        assertEq(tickQueue.length, 2, "queue length should be 2");
        assertEq(tickQueue.head, created[0].orderId, "head unchanged");
        assertEq(tickQueue.tail, created[2].orderId, "tail unchanged");
    }

    function test_unlinkSingleElement() public {
        PoolKey memory key = creatorCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(key.currency0) == address(creatorCoin);
        address orderCoin = _orderCoin(key, isCurrency0);

        (uint256[] memory orderSizes, int24[] memory orderTicks) = _buildDeterministicOrders(key, isCurrency0, 1, 25e18);

        _fundAndApprove(users.seller, orderCoin, orderSizes[0]);

        vm.recordLogs();
        vm.prank(users.seller);
        limitOrderBook.create{value: orderCoin == address(0) ? orderSizes[0] : 0}(key, isCurrency0, orderSizes, orderTicks, users.seller);

        CreatedOrderLog[] memory created = _decodeCreatedLogs(vm.getRecordedLogs());

        // Withdraw only order
        bytes32[] memory orderIds = new bytes32[](1);
        orderIds[0] = created[0].orderId;
        vm.prank(users.seller);
        limitOrderBook.withdraw(orderIds, orderCoin, 0, users.seller);

        QueueSnapshot memory tickQueue = _tickQueueSnapshot(created[0].poolKeyHash, orderCoin, created[0].tick);
        assertEq(tickQueue.length, 0, "queue should be empty");
        assertEq(tickQueue.head, bytes32(0), "head should be cleared");
        assertEq(tickQueue.tail, bytes32(0), "tail should be cleared");
    }

    function test_bitmapSetIfFirstWhenEmpty() public {
        PoolKey memory key = creatorCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(key.currency0) == address(creatorCoin);
        address orderCoin = _orderCoin(key, isCurrency0);

        (uint256[] memory orderSizes, int24[] memory orderTicks) = _buildDeterministicOrders(key, isCurrency0, 1, 25e18);

        _fundAndApprove(users.seller, orderCoin, orderSizes[0]);

        vm.prank(users.seller);
        limitOrderBook.create{value: orderCoin == address(0) ? orderSizes[0] : 0}(key, isCurrency0, orderSizes, orderTicks, users.seller);

        // Verify bitmap is set
        bytes32 poolKeyHash = keccak256(abi.encode(key));
        int24 fillableTick = _fillableTick(isCurrency0, orderTicks[0], key.tickSpacing);
        assertTrue(_isTickInitialized(poolKeyHash, orderCoin, fillableTick, key.tickSpacing), "tick should be initialized");
    }

    function test_bitmapSetIfFirstWhenNonEmpty() public {
        PoolKey memory key = creatorCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(key.currency0) == address(creatorCoin);
        address orderCoin = _orderCoin(key, isCurrency0);

        // Create two orders at same tick
        int24 tick = _getValidTick(key, isCurrency0);
        uint256[] memory orderSizes = new uint256[](2);
        orderSizes[0] = 25e18;
        orderSizes[1] = 25e18;
        int24[] memory orderTicks = new int24[](2);
        orderTicks[0] = tick;
        orderTicks[1] = tick;

        uint256 totalSize = orderSizes[0] + orderSizes[1];
        _fundAndApprove(users.seller, orderCoin, totalSize);

        vm.prank(users.seller);
        limitOrderBook.create{value: orderCoin == address(0) ? totalSize : 0}(key, isCurrency0, orderSizes, orderTicks, users.seller);

        // Verify bitmap is still set (second enqueue didn't break it)
        bytes32 poolKeyHash = keccak256(abi.encode(key));
        int24 fillableTick = _fillableTick(isCurrency0, tick, key.tickSpacing);
        assertTrue(_isTickInitialized(poolKeyHash, orderCoin, fillableTick, key.tickSpacing), "tick should be initialized");

        QueueSnapshot memory tickQueue = _tickQueueSnapshot(poolKeyHash, orderCoin, fillableTick);
        assertEq(tickQueue.length, 2, "should have 2 orders at same tick");
    }

    function test_bitmapClearIfEmptyWhenLastRemoved() public {
        PoolKey memory key = creatorCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(key.currency0) == address(creatorCoin);
        address orderCoin = _orderCoin(key, isCurrency0);

        (uint256[] memory orderSizes, int24[] memory orderTicks) = _buildDeterministicOrders(key, isCurrency0, 1, 25e18);

        _fundAndApprove(users.seller, orderCoin, orderSizes[0]);

        vm.recordLogs();
        vm.prank(users.seller);
        limitOrderBook.create{value: orderCoin == address(0) ? orderSizes[0] : 0}(key, isCurrency0, orderSizes, orderTicks, users.seller);

        CreatedOrderLog[] memory created = _decodeCreatedLogs(vm.getRecordedLogs());
        bytes32 poolKeyHash = created[0].poolKeyHash;

        // Withdraw order - should clear bitmap
        bytes32[] memory orderIds = new bytes32[](1);
        orderIds[0] = created[0].orderId;
        vm.prank(users.seller);
        limitOrderBook.withdraw(orderIds, orderCoin, 0, users.seller);

        int24 fillableTick = _fillableTick(isCurrency0, orderTicks[0], key.tickSpacing);
        assertFalse(_isTickInitialized(poolKeyHash, orderCoin, fillableTick, key.tickSpacing), "tick should be cleared");
    }

    function test_bitmapClearIfEmptyWhenStillHasOrders() public {
        PoolKey memory key = creatorCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(key.currency0) == address(creatorCoin);
        address orderCoin = _orderCoin(key, isCurrency0);

        // Create two orders at same tick
        int24 tick = _getValidTick(key, isCurrency0);
        uint256[] memory orderSizes = new uint256[](2);
        orderSizes[0] = 25e18;
        orderSizes[1] = 25e18;
        int24[] memory orderTicks = new int24[](2);
        orderTicks[0] = tick;
        orderTicks[1] = tick;

        uint256 totalSize = orderSizes[0] + orderSizes[1];
        _fundAndApprove(users.seller, orderCoin, totalSize);

        vm.recordLogs();
        vm.prank(users.seller);
        limitOrderBook.create{value: orderCoin == address(0) ? totalSize : 0}(key, isCurrency0, orderSizes, orderTicks, users.seller);

        CreatedOrderLog[] memory created = _decodeCreatedLogs(vm.getRecordedLogs());
        bytes32 poolKeyHash = created[0].poolKeyHash;

        // Withdraw first order - bitmap should still be set
        bytes32[] memory orderIds = new bytes32[](1);
        orderIds[0] = created[0].orderId;
        vm.prank(users.seller);
        limitOrderBook.withdraw(orderIds, orderCoin, 0, users.seller);

        int24 fillableTick = _fillableTick(isCurrency0, tick, key.tickSpacing);
        assertTrue(_isTickInitialized(poolKeyHash, orderCoin, fillableTick, key.tickSpacing), "tick should still be initialized");

        QueueSnapshot memory tickQueue = _tickQueueSnapshot(poolKeyHash, orderCoin, fillableTick);
        assertEq(tickQueue.length, 1, "should have 1 order remaining");
    }

    function _fundAndApprove(address user, address token, uint256 amount) internal {
        if (token == address(0)) {
            vm.deal(user, amount);
        } else {
            deal(token, user, amount);
            vm.prank(user);
            IERC20(token).approve(address(limitOrderBook), amount);
        }
    }

    function _getValidTick(PoolKey memory key, bool isCurrency0) internal view returns (int24) {
        int24 currentTick = _currentTick(key);

        // Get a tick away from current price based on direction
        int24 offset = isCurrency0 ? key.tickSpacing * 2 : -key.tickSpacing * 2;
        int24 targetTick = currentTick + offset;

        // Align to tick spacing
        targetTick = _alignedTick(targetTick, key.tickSpacing);

        return targetTick;
    }
}
