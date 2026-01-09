// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {BaseTest} from "./utils/BaseTest.sol";

import {IZoraLimitOrderBook} from "../src/IZoraLimitOrderBook.sol";
import {LimitOrderTypes} from "../src/libs/LimitOrderTypes.sol";

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Vm} from "forge-std/Vm.sol";

contract LimitOrderWithdrawTest is BaseTest {
    function test_withdrawOrdersCancelsAll() public {
        PoolKey memory key = creatorCoin.getPoolKey();

        vm.recordLogs();
        _executeSingleHopSwapWithLimitOrders(users.seller, key, DEFAULT_LIMIT_ORDER_AMOUNT, _defaultMultiples(), _defaultPercentages());
        CreatedOrderLog[] memory created = _decodeCreatedLogs(vm.getRecordedLogs());
        assertGt(created.length, 0, "expected orders to be created");
        _assertOpenOrderState(users.seller, created[0].coin, created[0].poolKeyHash, created, key.tickSpacing);

        bytes32[] memory orderIds = _orderIds(created);
        address orderCoin = created[0].coin;
        uint256 tokenBalanceBefore = _balanceOf(orderCoin, users.seller);
        uint256 epochBefore = _poolEpoch(created[0].poolKeyHash);
        uint256 totalOrderSize = _sumOrderSizes(created);

        vm.recordLogs();
        vm.prank(users.seller);
        limitOrderBook.withdraw(orderIds, orderCoin, 0, users.seller);
        UpdatedOrderLog[] memory updates = _decodeUpdatedLogs(vm.getRecordedLogs());

        uint256 cancelled;
        for (uint256 i; i < updates.length; ++i) {
            if (updates[i].maker != users.seller) continue;
            if (!updates[i].isCancelled) continue;
            ++cancelled;
        }

        assertEq(cancelled, orderIds.length, "all orders should cancel");

        uint256 tokenBalanceAfter = _balanceOf(orderCoin, users.seller);
        assertApproxEqAbs(tokenBalanceAfter, tokenBalanceBefore + totalOrderSize, 5, "token refund mismatch");
        assertEq(_poolEpoch(created[0].poolKeyHash), epochBefore, "withdraw should not change epoch");

        for (uint256 i; i < created.length; ++i) {
            QueueSnapshot memory tickQueue = _tickQueueSnapshot(created[i].poolKeyHash, orderCoin, created[i].tick);
            assertEq(tickQueue.length, 0, "tick queue length");
            assertEq(tickQueue.balance, 0, "tick queue balance");
            assertFalse(_isTickInitialized(created[i].poolKeyHash, orderCoin, created[i].tick, key.tickSpacing), "tick bitmap still set");
        }
    }

    function test_withdrawOrdersRevertsForMixedCoins() public {
        PoolKey memory creatorKey = creatorCoin.getPoolKey();
        PoolKey memory contentKey = contentCoin.getPoolKey();

        vm.recordLogs();
        _executeSingleHopSwapWithLimitOrders(users.seller, creatorKey, DEFAULT_LIMIT_ORDER_AMOUNT, _defaultMultiples(), _defaultPercentages());
        CreatedOrderLog[] memory creatorOrders = _decodeCreatedLogs(vm.getRecordedLogs());
        assertGt(creatorOrders.length, 0, "expected creator orders");

        // Content pool requires multi-hop routing: ZORA → SharedToken → ContentCoin
        vm.recordLogs();
        PoolKey[] memory contentRoute = new PoolKey[](2);
        contentRoute[0] = creatorKey; // First hop: ZORA → SharedToken
        contentRoute[1] = contentKey; // Second hop: SharedToken → ContentCoin
        _executeMultiHopSwapWithLimitOrders(users.seller, contentRoute, DEFAULT_LIMIT_ORDER_AMOUNT, _defaultMultiples(), _defaultPercentages());
        CreatedOrderLog[] memory contentOrders = _decodeCreatedLogs(vm.getRecordedLogs());
        assertGt(contentOrders.length, 0, "expected content orders");

        bytes32[] memory mixed = new bytes32[](creatorOrders.length + contentOrders.length);
        for (uint256 i; i < creatorOrders.length; ++i) {
            mixed[i] = creatorOrders[i].orderId;
        }
        for (uint256 i; i < contentOrders.length; ++i) {
            mixed[creatorOrders.length + i] = contentOrders[i].orderId;
        }

        // First content order will trigger the mismatch
        bytes32 mismatchOrderId = contentOrders[0].orderId;
        address expectedCoin = creatorOrders[0].coin;
        address actualCoin = contentOrders[0].coin;

        vm.expectRevert(abi.encodeWithSelector(IZoraLimitOrderBook.CoinMismatch.selector, mismatchOrderId, expectedCoin, actualCoin));
        vm.prank(users.seller);
        limitOrderBook.withdraw(mixed, expectedCoin, 0, users.seller);

        _assertOpenOrderState(users.seller, creatorOrders[0].coin, creatorOrders[0].poolKeyHash, creatorOrders, creatorKey.tickSpacing);
        _assertOpenOrderState(users.seller, contentOrders[0].coin, contentOrders[0].poolKeyHash, contentOrders, contentKey.tickSpacing);
    }

    function test_withdrawOrdersRevertsForRecipientZero() public {
        PoolKey memory key = creatorCoin.getPoolKey();

        vm.recordLogs();
        _executeSingleHopSwapWithLimitOrders(users.seller, key, DEFAULT_LIMIT_ORDER_AMOUNT, _defaultMultiples(), _defaultPercentages());
        CreatedOrderLog[] memory created = _decodeCreatedLogs(vm.getRecordedLogs());
        assertGt(created.length, 0, "expected orders to be created");

        bytes32[] memory orderIds = _orderIds(created);
        address orderCoin = created[0].coin;

        vm.expectRevert(IZoraLimitOrderBook.AddressZero.selector);
        vm.prank(users.seller);
        limitOrderBook.withdraw(orderIds, orderCoin, 0, address(0));
    }

    function test_withdrawOrdersRevertsForNonMaker() public {
        PoolKey memory key = creatorCoin.getPoolKey();

        vm.recordLogs();
        _executeSingleHopSwapWithLimitOrders(users.seller, key, DEFAULT_LIMIT_ORDER_AMOUNT, _defaultMultiples(), _defaultPercentages());
        CreatedOrderLog[] memory created = _decodeCreatedLogs(vm.getRecordedLogs());
        bytes32[] memory orderIds = _orderIds(created);
        address orderCoin = created[0].coin;

        vm.expectRevert(IZoraLimitOrderBook.OrderNotMaker.selector);
        vm.prank(users.buyer);
        limitOrderBook.withdraw(orderIds, orderCoin, 0, users.buyer);

        _assertOpenOrderState(users.seller, created[0].coin, created[0].poolKeyHash, created, key.tickSpacing);
    }

    function test_withdrawOrdersRevertsOnInvalidOrder() public {
        PoolKey memory key = creatorCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(key.currency0) == address(creatorCoin);

        uint256[] memory orderSizes = new uint256[](1);
        orderSizes[0] = 75e18;
        (, int24[] memory orderTicks) = _buildDeterministicOrders(key, isCurrency0, 1, 1);
        (CreatedOrderLog[] memory created, address orderCoin) = _createOrders(users.seller, key, isCurrency0, orderSizes, orderTicks);

        bytes32[] memory mixed = new bytes32[](2);
        mixed[0] = created[0].orderId;
        mixed[1] = bytes32(uint256(123));

        vm.expectRevert(IZoraLimitOrderBook.InvalidOrder.selector);
        vm.prank(users.seller);
        limitOrderBook.withdraw(mixed, orderCoin, 0, users.seller);
    }

    function test_withdrawOrdersRevertsOnClosedOrder() public {
        PoolKey memory key = creatorCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(key.currency0) == address(creatorCoin);

        uint256[] memory orderSizes = new uint256[](1);
        orderSizes[0] = 90e18;
        (, int24[] memory orderTicks) = _buildDeterministicOrders(key, isCurrency0, 1, 1);
        (CreatedOrderLog[] memory created, address orderCoin) = _createOrders(users.seller, key, isCurrency0, orderSizes, orderTicks);

        limitOrderBook.forceOrderStatus(created[0].orderId, LimitOrderTypes.OrderStatus.INACTIVE);

        bytes32[] memory ids = new bytes32[](1);
        ids[0] = created[0].orderId;

        vm.expectRevert(IZoraLimitOrderBook.OrderClosed.selector);
        vm.prank(users.seller);
        limitOrderBook.withdraw(ids, orderCoin, 0, users.seller);
    }

    function test_cancelOrderFullCancellationMarksInactive() public {
        PoolKey memory key = creatorCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(key.currency0) == address(creatorCoin);

        uint256[] memory orderSizes = new uint256[](1);
        orderSizes[0] = 500e18;
        (, int24[] memory orderTicks) = _buildDeterministicOrders(key, isCurrency0, 1, 1);
        (CreatedOrderLog[] memory created, address orderCoin) = _createOrders(users.seller, key, isCurrency0, orderSizes, orderTicks);

        bytes32[] memory ids = new bytes32[](1);
        ids[0] = created[0].orderId;

        vm.prank(users.seller);
        limitOrderBook.withdraw(ids, orderCoin, 0, users.seller);

        LimitOrderTypes.LimitOrder memory orderState = limitOrderBook.exposedOrder(created[0].orderId);
        assertEq(uint8(orderState.status), uint8(LimitOrderTypes.OrderStatus.INACTIVE), "order should be marked inactive");

        QueueSnapshot memory tickQueue = _tickQueueSnapshot(created[0].poolKeyHash, orderCoin, created[0].tick);
        assertEq(tickQueue.length, 0, "tick queue length");
        assertEq(tickQueue.balance, 0, "tick queue balance");
        assertFalse(_isTickInitialized(created[0].poolKeyHash, orderCoin, created[0].tick, key.tickSpacing), "tick bitmap should clear");
    }

    function test_withdrawWithMinAmountOutStopsEarly() public {
        PoolKey memory key = creatorCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(key.currency0) == address(creatorCoin);

        uint256[] memory orderSizes = new uint256[](3);
        orderSizes[0] = 100e18;
        orderSizes[1] = 200e18;
        orderSizes[2] = 300e18;
        (, int24[] memory orderTicks) = _buildDeterministicOrders(key, isCurrency0, orderSizes.length, 1);
        (CreatedOrderLog[] memory created, address orderCoin) = _createOrders(users.seller, key, isCurrency0, orderSizes, orderTicks);

        bytes32[] memory orderIds = _orderIds(created);
        uint256 tokenBalanceBefore = _balanceOf(orderCoin, users.seller);

        // Use actual created order sizes (which may differ due to liquidity rounding)
        uint256 actualFirstTwo = created[0].size + created[1].size;

        vm.recordLogs();
        vm.prank(users.seller);
        limitOrderBook.withdraw(orderIds, orderCoin, actualFirstTwo, users.seller);
        UpdatedOrderLog[] memory updates = _decodeUpdatedLogs(vm.getRecordedLogs());

        // Should have cancelled exactly 2 orders
        uint256 cancelled;
        for (uint256 i; i < updates.length; ++i) {
            if (updates[i].maker != users.seller) continue;
            if (updates[i].isCancelled) ++cancelled;
        }
        assertEq(cancelled, 2, "should cancel first two orders");

        // Third order should still be open
        LimitOrderTypes.LimitOrder memory thirdOrder = limitOrderBook.exposedOrder(created[2].orderId);
        assertEq(uint8(thirdOrder.status), uint8(LimitOrderTypes.OrderStatus.OPEN), "third order should still be open");

        uint256 tokenBalanceAfter = _balanceOf(orderCoin, users.seller);
        assertApproxEqAbs(tokenBalanceAfter, tokenBalanceBefore + actualFirstTwo, 5, "token refund should match first two orders");
    }

    function test_withdrawWithMinAmountOutRevertsIfNotReached() public {
        PoolKey memory key = creatorCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(key.currency0) == address(creatorCoin);

        uint256[] memory orderSizes = new uint256[](2);
        orderSizes[0] = 100e18;
        orderSizes[1] = 200e18;
        (, int24[] memory orderTicks) = _buildDeterministicOrders(key, isCurrency0, orderSizes.length, 1);
        (CreatedOrderLog[] memory created, address orderCoin) = _createOrders(users.seller, key, isCurrency0, orderSizes, orderTicks);

        bytes32[] memory orderIds = _orderIds(created);

        // Use actual created sizes and request slightly more
        uint256 actualTotal = created[0].size + created[1].size;
        uint256 minAmountOut = actualTotal + 1;

        vm.expectRevert(abi.encodeWithSelector(IZoraLimitOrderBook.MinAmountNotReached.selector, actualTotal, minAmountOut));
        vm.prank(users.seller);
        limitOrderBook.withdraw(orderIds, orderCoin, minAmountOut, users.seller);
    }

    function test_withdrawWithZeroMinAmountOutCancelsAll() public {
        PoolKey memory key = creatorCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(key.currency0) == address(creatorCoin);

        uint256[] memory orderSizes = new uint256[](3);
        orderSizes[0] = 100e18;
        orderSizes[1] = 200e18;
        orderSizes[2] = 300e18;
        (, int24[] memory orderTicks) = _buildDeterministicOrders(key, isCurrency0, orderSizes.length, 1);
        (CreatedOrderLog[] memory created, address orderCoin) = _createOrders(users.seller, key, isCurrency0, orderSizes, orderTicks);

        bytes32[] memory orderIds = _orderIds(created);
        uint256 tokenBalanceBefore = _balanceOf(orderCoin, users.seller);
        uint256 totalSize = orderSizes[0] + orderSizes[1] + orderSizes[2];

        vm.recordLogs();
        vm.prank(users.seller);
        limitOrderBook.withdraw(orderIds, orderCoin, 0, users.seller);
        UpdatedOrderLog[] memory updates = _decodeUpdatedLogs(vm.getRecordedLogs());

        // All orders should be cancelled
        uint256 cancelled;
        for (uint256 i; i < updates.length; ++i) {
            if (updates[i].maker != users.seller) continue;
            if (updates[i].isCancelled) ++cancelled;
        }
        assertEq(cancelled, 3, "all orders should cancel");

        uint256 tokenBalanceAfter = _balanceOf(orderCoin, users.seller);
        assertApproxEqAbs(tokenBalanceAfter, tokenBalanceBefore + totalSize, 5, "token refund should match total");
    }

    function test_withdrawRevertsOnEmptyOrderIds() public {
        bytes32[] memory orderIds = new bytes32[](0);

        vm.expectRevert(IZoraLimitOrderBook.InvalidOrder.selector);
        vm.prank(users.seller);
        limitOrderBook.withdraw(orderIds, address(0), 0, users.seller);
    }

    /// @notice Tests that withdrawing filled orders reverts appropriately
    function test_withdraw_filledOrdersReverts() public {
        PoolKey memory key = creatorCoin.getPoolKey();

        vm.recordLogs();
        _executeSingleHopSwapWithLimitOrders(users.seller, key, DEFAULT_LIMIT_ORDER_AMOUNT, _defaultMultiples(), _defaultPercentages());
        CreatedOrderLog[] memory created = _decodeCreatedLogs(vm.getRecordedLogs());
        address orderCoin = created[0].coin;

        // Manually mark first order as filled
        limitOrderBook.forceOrderStatus(created[0].orderId, LimitOrderTypes.OrderStatus.FILLED);

        // Try to withdraw filled order - should revert
        bytes32[] memory orderIds = new bytes32[](1);
        orderIds[0] = created[0].orderId;

        vm.prank(users.seller);
        vm.expectRevert(IZoraLimitOrderBook.OrderClosed.selector);
        limitOrderBook.withdraw(orderIds, orderCoin, 0, users.seller);
    }

    /// @notice Tests that bitmap is cleaned when last order at tick is withdrawn
    function test_withdraw_lastOrderAtTick_cleansBitmap() public {
        PoolKey memory key = creatorCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(key.currency0) == address(creatorCoin);
        address orderCoin = _orderCoin(key, isCurrency0);

        // Create single order
        (uint256[] memory sizes, int24[] memory ticks) = _buildDeterministicOrders(key, isCurrency0, 1, 50e18);
        _fundAndApprove(users.seller, orderCoin, sizes[0]);

        vm.recordLogs();
        vm.prank(users.seller);
        limitOrderBook.create{value: orderCoin == address(0) ? sizes[0] : 0}(key, isCurrency0, sizes, ticks, users.seller);

        CreatedOrderLog[] memory created = _decodeCreatedLogs(vm.getRecordedLogs());
        bytes32 poolKeyHash = created[0].poolKeyHash;
        int24 tick = ticks[0];

        // Verify bitmap set
        assertTrue(_isTickInitialized(poolKeyHash, orderCoin, tick, key.tickSpacing), "tick should be initialized");

        // Withdraw order
        bytes32[] memory orderIds = new bytes32[](1);
        orderIds[0] = created[0].orderId;
        vm.prank(users.seller);
        limitOrderBook.withdraw(orderIds, orderCoin, 0, users.seller);

        // Bitmap should be cleared
        assertFalse(_isTickInitialized(poolKeyHash, orderCoin, tick, key.tickSpacing), "tick should be cleared");
    }

    function test_withdraw_filledOrder_makerBalanceUnchanged() public {
        PoolKey memory key = creatorCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(key.currency0) == address(creatorCoin);
        address orderCoin = _orderCoin(key, isCurrency0);

        // Create 1 order
        uint256[] memory orderSizes = new uint256[](1);
        orderSizes[0] = 100 ether;
        (, int24[] memory orderTicks) = _buildDeterministicOrders(key, isCurrency0, 1, 1);
        (CreatedOrderLog[] memory created, ) = _createOrders(users.seller, key, isCurrency0, orderSizes, orderTicks);

        uint256 balanceAfterCreate = _makerBalance(users.seller, orderCoin);
        assertGt(balanceAfterCreate, 0, "balance should be positive after create");

        // Mark order as filled
        limitOrderBook.forceOrderStatus(created[0].orderId, LimitOrderTypes.OrderStatus.FILLED);

        // Try to withdraw filled order - should revert without touching balance
        bytes32[] memory orderIds = new bytes32[](1);
        orderIds[0] = created[0].orderId;

        vm.prank(users.seller);
        vm.expectRevert(IZoraLimitOrderBook.OrderClosed.selector);
        limitOrderBook.withdraw(orderIds, orderCoin, 0, users.seller);

        // Balance should be unchanged (transaction reverted)
        assertEq(_makerBalance(users.seller, orderCoin), balanceAfterCreate, "balance should be unchanged after revert");
    }

    function test_withdraw_mixedFilledAndOpen_revertsOnFirstFilled() public {
        PoolKey memory key = creatorCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(key.currency0) == address(creatorCoin);
        address orderCoin = _orderCoin(key, isCurrency0);

        // Create 3 orders
        uint256[] memory orderSizes = new uint256[](3);
        orderSizes[0] = 100 ether;
        orderSizes[1] = 200 ether;
        orderSizes[2] = 300 ether;
        (, int24[] memory orderTicks) = _buildDeterministicOrders(key, isCurrency0, 3, 1);
        (CreatedOrderLog[] memory created, ) = _createOrders(users.seller, key, isCurrency0, orderSizes, orderTicks);

        uint256 balanceAfterCreate = _makerBalance(users.seller, orderCoin);

        // Mark second order as filled
        limitOrderBook.forceOrderStatus(created[1].orderId, LimitOrderTypes.OrderStatus.FILLED);

        // Try to withdraw all 3 orders - should revert when hitting the filled one
        bytes32[] memory orderIds = new bytes32[](3);
        orderIds[0] = created[0].orderId;
        orderIds[1] = created[1].orderId;
        orderIds[2] = created[2].orderId;

        vm.prank(users.seller);
        vm.expectRevert(IZoraLimitOrderBook.OrderClosed.selector);
        limitOrderBook.withdraw(orderIds, orderCoin, 0, users.seller);

        // Balance should be unchanged (entire transaction reverted, including first order)
        assertEq(_makerBalance(users.seller, orderCoin), balanceAfterCreate, "balance unchanged after revert");
    }

    function test_withdraw_withMinAmountOut_filledOrder_revertsBeforeReachingThreshold() public {
        PoolKey memory key = creatorCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(key.currency0) == address(creatorCoin);
        address orderCoin = _orderCoin(key, isCurrency0);

        // Create 2 orders
        uint256[] memory orderSizes = new uint256[](2);
        orderSizes[0] = 100 ether;
        orderSizes[1] = 200 ether;
        (, int24[] memory orderTicks) = _buildDeterministicOrders(key, isCurrency0, 2, 1);
        (CreatedOrderLog[] memory created, ) = _createOrders(users.seller, key, isCurrency0, orderSizes, orderTicks);

        uint256 balanceAfterCreate = _makerBalance(users.seller, orderCoin);

        // Mark first order as filled
        limitOrderBook.forceOrderStatus(created[0].orderId, LimitOrderTypes.OrderStatus.FILLED);

        // Try to withdraw both with minAmountOut - should revert on first filled order
        bytes32[] memory orderIds = new bytes32[](2);
        orderIds[0] = created[0].orderId;
        orderIds[1] = created[1].orderId;

        uint256 minAmountOut = created[1].size; // Even though we want the second order

        vm.prank(users.seller);
        vm.expectRevert(IZoraLimitOrderBook.OrderClosed.selector);
        limitOrderBook.withdraw(orderIds, orderCoin, minAmountOut, users.seller);

        // Balance unchanged
        assertEq(_makerBalance(users.seller, orderCoin), balanceAfterCreate, "balance unchanged after revert");
    }

    function test_makerBalanceUpdated_emittedOnWithdraw() public {
        PoolKey memory key = creatorCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(key.currency0) == address(creatorCoin);

        uint256[] memory orderSizes = new uint256[](2);
        orderSizes[0] = 100 ether;
        orderSizes[1] = 200 ether;
        (, int24[] memory orderTicks) = _buildDeterministicOrders(key, isCurrency0, orderSizes.length, 1);
        (CreatedOrderLog[] memory created, address orderCoin) = _createOrders(users.seller, key, isCurrency0, orderSizes, orderTicks);

        bytes32[] memory orderIds = _orderIds(created);

        vm.recordLogs();
        vm.prank(users.seller);
        limitOrderBook.withdraw(orderIds, orderCoin, 0, users.seller);

        // Find MakerBalanceUpdated events
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 eventCount;
        uint256 finalBalance;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == IZoraLimitOrderBook.MakerBalanceUpdated.selector) {
                address eventMaker = address(uint160(uint256(logs[i].topics[1])));
                address eventCoin = address(uint160(uint256(logs[i].topics[2])));
                if (eventMaker == users.seller && eventCoin == orderCoin) {
                    finalBalance = abi.decode(logs[i].data, (uint256));
                    ++eventCount;
                }
            }
        }

        // Should have 2 events (one per order cancelled)
        assertEq(eventCount, 2, "should emit 2 MakerBalanceUpdated events");
        assertEq(finalBalance, 0, "final balance should be zero");
        assertEq(_makerBalance(users.seller, orderCoin), 0, "maker balance should be zero");
    }

    function test_withdraw_ethBackedOrders() public {
        PoolKey memory key = creatorCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(key.currency0) == address(creatorCoin);
        address orderCoin = _orderCoin(key, isCurrency0);

        // Skip if this pool doesn't use ETH
        if (orderCoin != address(0)) {
            return;
        }

        // Create ETH-backed orders
        uint256[] memory orderSizes = new uint256[](2);
        orderSizes[0] = 1 ether;
        orderSizes[1] = 2 ether;
        (, int24[] memory orderTicks) = _buildDeterministicOrders(key, isCurrency0, orderSizes.length, 1);
        (CreatedOrderLog[] memory created, ) = _createOrders(users.seller, key, isCurrency0, orderSizes, orderTicks);

        bytes32[] memory orderIds = _orderIds(created);
        uint256 ethBalanceBefore = users.seller.balance;
        uint256 totalSize = created[0].size + created[1].size;

        // Withdraw ETH-backed orders
        vm.prank(users.seller);
        limitOrderBook.withdraw(orderIds, orderCoin, 0, users.seller);

        // Verify ETH was refunded
        uint256 ethBalanceAfter = users.seller.balance;
        assertApproxEqAbs(ethBalanceAfter, ethBalanceBefore + totalSize, 5, "ETH refund mismatch");
    }

    function test_withdraw_ethBackedOrders_withMinAmountOut() public {
        PoolKey memory key = creatorCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(key.currency0) == address(creatorCoin);
        address orderCoin = _orderCoin(key, isCurrency0);

        // Skip if this pool doesn't use ETH
        if (orderCoin != address(0)) {
            return;
        }

        // Create 3 ETH-backed orders
        uint256[] memory orderSizes = new uint256[](3);
        orderSizes[0] = 1 ether;
        orderSizes[1] = 2 ether;
        orderSizes[2] = 3 ether;
        (, int24[] memory orderTicks) = _buildDeterministicOrders(key, isCurrency0, orderSizes.length, 1);
        (CreatedOrderLog[] memory created, ) = _createOrders(users.seller, key, isCurrency0, orderSizes, orderTicks);

        bytes32[] memory orderIds = _orderIds(created);
        uint256 ethBalanceBefore = users.seller.balance;
        uint256 firstTwoSize = created[0].size + created[1].size;

        // Withdraw with minAmountOut - should stop after first two orders
        vm.prank(users.seller);
        limitOrderBook.withdraw(orderIds, orderCoin, firstTwoSize, users.seller);

        // Verify first two orders' ETH was refunded
        uint256 ethBalanceAfter = users.seller.balance;
        assertApproxEqAbs(ethBalanceAfter, ethBalanceBefore + firstTwoSize, 5, "ETH refund mismatch");

        // Third order should still be open
        LimitOrderTypes.LimitOrder memory thirdOrder = limitOrderBook.exposedOrder(created[2].orderId);
        assertEq(uint8(thirdOrder.status), uint8(LimitOrderTypes.OrderStatus.OPEN), "third order should still be open");
    }

    function _balanceOf(address token, address account) private view returns (uint256) {
        if (token == address(0)) {
            return account.balance;
        }
        return IERC20(token).balanceOf(account);
    }

    function _createOrders(
        address maker,
        PoolKey memory key,
        bool isCurrency0,
        uint256[] memory orderSizes,
        int24[] memory orderTicks
    ) private returns (CreatedOrderLog[] memory created, address orderCoin) {
        require(orderSizes.length == orderTicks.length, "order configuration mismatch");

        orderCoin = _orderCoin(key, isCurrency0);
        uint256 totalSize;
        for (uint256 i; i < orderSizes.length; ++i) {
            totalSize += orderSizes[i];
        }

        _fundAndApprove(maker, orderCoin, totalSize);

        vm.recordLogs();
        vm.prank(maker);
        limitOrderBook.create{value: orderCoin == address(0) ? totalSize : 0}(key, isCurrency0, orderSizes, orderTicks, maker);
        created = _decodeCreatedLogs(vm.getRecordedLogs());
    }

    function _fundAndApprove(address maker, address coin, uint256 amount) private {
        if (coin == address(0)) {
            vm.deal(maker, amount);
            return;
        }

        deal(coin, maker, amount);
        vm.startPrank(maker);
        IERC20(coin).approve(address(limitOrderBook), amount);
        vm.stopPrank();
    }

    /// @notice Tests that reentrancy during withdrawal is prevented by CEI pattern
    function test_withdraw_reentrancyPrevented() public {
        PoolKey memory key = creatorCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(key.currency0) == address(creatorCoin);
        address orderCoin = _orderCoin(key, isCurrency0);

        // Create 2 orders for the seller
        uint256[] memory orderSizes = new uint256[](2);
        orderSizes[0] = 100 ether;
        orderSizes[1] = 100 ether;
        (, int24[] memory orderTicks) = _buildDeterministicOrders(key, isCurrency0, 2, 1);
        (CreatedOrderLog[] memory created, ) = _createOrders(users.seller, key, isCurrency0, orderSizes, orderTicks);

        // Deploy malicious recipient that will try to re-enter
        ReentrancyAttacker attacker = new ReentrancyAttacker(limitOrderBook, created[1].orderId, orderCoin);

        // Withdraw first order to the attacker contract
        // The attacker will try to withdraw the second order during the callback
        bytes32[] memory orderIds = new bytes32[](1);
        orderIds[0] = created[0].orderId;

        vm.prank(users.seller);
        limitOrderBook.withdraw(orderIds, orderCoin, 0, address(attacker));

        // Verify first order was withdrawn successfully
        LimitOrderTypes.LimitOrder memory firstOrder = limitOrderBook.exposedOrder(created[0].orderId);
        assertEq(uint8(firstOrder.status), uint8(LimitOrderTypes.OrderStatus.INACTIVE), "first order should be inactive");

        // Verify attacker's reentrancy attempt failed (second order still open)
        // Note: The attack would fail with OrderClosed if order was already marked inactive,
        // or it would succeed if state wasn't updated before external call
        assertFalse(attacker.attackSucceeded(), "reentrancy attack should have failed");

        // Second order should still be open (attacker couldn't steal it)
        LimitOrderTypes.LimitOrder memory secondOrder = limitOrderBook.exposedOrder(created[1].orderId);
        assertEq(uint8(secondOrder.status), uint8(LimitOrderTypes.OrderStatus.OPEN), "second order should still be open");
    }
}

/// @notice Malicious contract that attempts reentrancy during token receipt
contract ReentrancyAttacker {
    IZoraLimitOrderBook public limitOrderBook;
    bytes32 public targetOrderId;
    address public coin;
    bool public attackSucceeded;
    bool public attacked;

    constructor(IZoraLimitOrderBook _limitOrderBook, bytes32 _targetOrderId, address _coin) {
        limitOrderBook = _limitOrderBook;
        targetOrderId = _targetOrderId;
        coin = _coin;
    }

    /// @notice Called when receiving ERC20 tokens - attempts reentrancy
    fallback() external payable {
        _tryAttack();
    }

    receive() external payable {
        _tryAttack();
    }

    function _tryAttack() internal {
        if (!attacked) {
            attacked = true;
            // Try to withdraw another order during the callback
            bytes32[] memory orderIds = new bytes32[](1);
            orderIds[0] = targetOrderId;

            try limitOrderBook.withdraw(orderIds, coin, 0, address(this)) {
                attackSucceeded = true;
            } catch {
                attackSucceeded = false;
            }
        }
    }
}
