// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {BaseTest} from "./utils/BaseTest.sol";
import {IZoraLimitOrderBook} from "../src/IZoraLimitOrderBook.sol";
import {LimitOrderCommon} from "../src/libs/LimitOrderCommon.sol";
import {CoinCommon} from "@zoralabs/coins/src/libs/CoinCommon.sol";
import {ICoin} from "@zoralabs/coins/src/interfaces/ICoin.sol";
import {LimitOrderTypes} from "../src/libs/LimitOrderTypes.sol";

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract LimitOrderFillTest is BaseTest {
    function test_debugCreateMakerBalance() public {
        PoolKey memory key = creatorCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(key.currency0) == address(creatorCoin);
        address orderCoin = LimitOrderCommon.getOrderCoin(key, isCurrency0);

        (uint256[] memory orderSizes, int24[] memory orderTicks) = _buildDeterministicOrders(key, isCurrency0, 1, 25e18);
        uint256 totalSize = orderSizes[0];

        if (orderCoin == address(0)) {
            vm.deal(users.seller, totalSize);
        } else {
            deal(orderCoin, users.seller, totalSize);
            vm.prank(users.seller);
            IERC20(orderCoin).approve(address(limitOrderBook), totalSize);
        }

        vm.prank(users.seller);
        limitOrderBook.create{value: orderCoin == address(0) ? totalSize : 0}(key, isCurrency0, orderSizes, orderTicks, users.seller);

        // Contract view
        uint256 onchainBalance = limitOrderBook.balanceOf(users.seller, orderCoin);
        assertEq(onchainBalance, totalSize, "maker balance from contract");
    }

    function test_fillWithNoOrdersIsNoop() public {
        PoolKey memory key = creatorCoin.getPoolKey();

        vm.recordLogs();
        limitOrderBook.fill(key, true, -type(int24).max, type(int24).max, 5, address(0));
        FilledOrderLog[] memory fills = _decodeFilledLogs(vm.getRecordedLogs());
        assertEq(fills.length, 0, "unexpected fills");
    }

    function test_fillRangeConsumesOrders() public {
        PoolKey memory key = creatorCoin.getPoolKey();

        vm.recordLogs();
        _executeSingleHopSwapWithLimitOrders(users.buyer, key, DEFAULT_LIMIT_ORDER_AMOUNT, _defaultMultiples(), _defaultPercentages());
        CreatedOrderLog[] memory created = _decodeCreatedLogs(vm.getRecordedLogs());
        assertGt(created.length, 0, "expected orders to be created");
        _assertOpenOrderState(users.buyer, created[0].coin, created[0].poolKeyHash, created, key.tickSpacing);

        // Move price past orders so they are fully crossed
        _movePriceBeyondTicksWithAutoFillDisabled(created);

        (int24 startTick, int24 endTick) = _tickWindow(created, key);
        bool isCurrency0 = created[0].isCurrency0;
        address orderCoin = created[0].coin;
        bytes32 poolKeyHash = created[0].poolKeyHash;
        uint256 epochBefore = _poolEpoch(poolKeyHash);

        vm.recordLogs();
        limitOrderBook.fill(key, isCurrency0, startTick, endTick, created.length, address(0));
        FilledOrderLog[] memory fills = _decodeFilledLogs(vm.getRecordedLogs());

        assertEq(fills.length, created.length, "fill count mismatch");
        for (uint256 i; i < fills.length; ++i) {
            assertEq(fills[i].maker, users.buyer, "maker mismatch");
            assertEq(fills[i].coinIn, orderCoin, "coin mismatch");
            assertEq(fills[i].fillReferral, address(0), "unexpected referral");
            assertEq(fills[i].fillReferralAmount, 0, "unexpected referral amount");
        }

        assertEq(_makerBalance(users.buyer, orderCoin), 0, "maker balance should be zero");
        _assertEpochIncrement(poolKeyHash, epochBefore);

        for (uint256 i; i < created.length; ++i) {
            QueueSnapshot memory tickQueue = _tickQueueSnapshot(poolKeyHash, orderCoin, created[i].tick);
            assertEq(tickQueue.length, 0, "tick queue length");
            assertEq(tickQueue.balance, 0, "tick queue balance");
            assertEq(tickQueue.head, bytes32(0), "tick queue head not cleared");
            assertEq(tickQueue.tail, bytes32(0), "tick queue tail not cleared");
            assertFalse(_isTickInitialized(poolKeyHash, orderCoin, created[i].tick, key.tickSpacing), "tick bitmap still set");
        }
    }

    function test_fillRangeConsumesOrdersWithAutoFillDisabledDuringSetup() public {
        PoolKey memory key = creatorCoin.getPoolKey();

        vm.recordLogs();
        _executeSingleHopSwapWithLimitOrders(users.buyer, key, DEFAULT_LIMIT_ORDER_AMOUNT, _defaultMultiples(), _defaultPercentages());
        CreatedOrderLog[] memory created = _decodeCreatedLogs(vm.getRecordedLogs());
        assertGt(created.length, 0, "expected orders to be created");
        _assertOpenOrderState(users.buyer, created[0].coin, created[0].poolKeyHash, created, key.tickSpacing);

        _movePriceBeyondTicksWithAutoFillDisabled(created);

        (int24 startTick, int24 endTick) = _tickWindow(created, key);
        bool isCurrency0 = created[0].isCurrency0;
        address orderCoin = created[0].coin;

        vm.recordLogs();
        limitOrderBook.fill(key, isCurrency0, startTick, endTick, created.length, address(0));
        for (uint256 i; i < created.length; ++i) {
            LimitOrderTypes.LimitOrder memory orderState = limitOrderBook.exposedOrder(created[i].orderId);
            assertEq(uint256(orderState.status), uint256(LimitOrderTypes.OrderStatus.FILLED), "order remained open");
        }
        assertEq(_makerBalance(users.buyer, orderCoin), 0, "maker balance should be zero");
    }

    function test_fillSentinelBoundsConsumesOrders() public {
        PoolKey memory key = creatorCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(key.currency0) == address(creatorCoin);
        address orderCoin = _orderCoin(key, isCurrency0);

        (uint256[] memory orderSizes, int24[] memory orderTicks) = _buildDeterministicOrders(key, isCurrency0, 2, 25e18);
        uint256 totalSize;
        for (uint256 i; i < orderSizes.length; ++i) {
            totalSize += orderSizes[i];
        }

        if (orderCoin == address(0)) {
            vm.deal(users.seller, totalSize);
        } else {
            deal(orderCoin, users.seller, totalSize);
            vm.startPrank(users.seller);
            IERC20(orderCoin).approve(address(limitOrderBook), totalSize);
            vm.stopPrank();
        }

        vm.recordLogs();
        vm.prank(users.seller);
        limitOrderBook.create{value: orderCoin == address(0) ? totalSize : 0}(key, isCurrency0, orderSizes, orderTicks, users.seller);
        CreatedOrderLog[] memory created = _decodeCreatedLogs(vm.getRecordedLogs());
        assertEq(created.length, orderSizes.length, "unexpected created order count");
        _assertOpenOrderState(users.seller, orderCoin, created[0].poolKeyHash, created, key.tickSpacing);

        _movePriceBeyondTicksWithAutoFillDisabled(created);

        (int24 startTick, int24 endTick) = _tickWindow(created, key);
        bytes32 poolKeyHash = created[0].poolKeyHash;
        uint256 epochBefore = _poolEpoch(poolKeyHash);

        vm.recordLogs();
        limitOrderBook.fill(key, isCurrency0, startTick, endTick, 0, address(0));
        FilledOrderLog[] memory fills = _decodeFilledLogs(vm.getRecordedLogs());

        assertEq(fills.length, created.length, "fill count mismatch");
        assertEq(_makerBalance(users.seller, orderCoin), 0, "maker balance should be zero");
        _assertEpochIncrement(poolKeyHash, epochBefore);

        for (uint256 i; i < created.length; ++i) {
            QueueSnapshot memory tickQueue = _tickQueueSnapshot(poolKeyHash, orderCoin, created[i].tick);
            assertEq(tickQueue.length, 0, "tick queue length");
            assertEq(tickQueue.balance, 0, "tick queue balance");
            assertFalse(_isTickInitialized(poolKeyHash, orderCoin, created[i].tick, key.tickSpacing), "tick bitmap still set");
        }
    }

    function test_fillSentinelBoundsAtMaxTickDoesNotRevert() public {
        PoolKey memory key = creatorCoin.getPoolKey();
        _setPoolTick(key, TickMath.MAX_TICK);

        vm.recordLogs();
        limitOrderBook.fill(key, true, -type(int24).max, type(int24).max, 1, address(0));
        FilledOrderLog[] memory fills = _decodeFilledLogs(vm.getRecordedLogs());
        assertEq(fills.length, 0, "no fills expected at sentinel boundary");
    }

    function test_fillSentinelBoundsAtMinTickDoesNotRevert() public {
        PoolKey memory key = creatorCoin.getPoolKey();
        _setPoolTick(key, TickMath.MIN_TICK);

        vm.recordLogs();
        limitOrderBook.fill(key, false, -type(int24).max, type(int24).max, 1, address(0));
        FilledOrderLog[] memory fills = _decodeFilledLogs(vm.getRecordedLogs());
        assertEq(fills.length, 0, "no fills expected at sentinel boundary");
    }

    function test_currency1StartSentinelAnchorsCurrentTick() public {
        PoolKey memory key = creatorCoin.getPoolKey();
        bool isCurrency0 = false;

        int24 anchorTick = _alignedTick(_currentTick(key), key.tickSpacing);
        _setPoolTick(key, anchorTick);

        (int24 resolvedStart, int24 resolvedEnd) = limitOrderBook.exposedResolveTickRange(key, isCurrency0, -type(int24).max, anchorTick - key.tickSpacing);

        assertEq(resolvedStart, anchorTick, "start sentinel should anchor current tick");
        assertEq(resolvedEnd, anchorTick - key.tickSpacing, "explicit end should be preserved");
    }

    function test_fillRangeUsesDefaultWhenMaxZero() public {
        PoolKey memory key = creatorCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(key.currency0) == address(creatorCoin);
        address orderCoin = _orderCoin(key, isCurrency0);

        limitOrderBook.setMaxFillCount(2);

        (uint256[] memory orderSizes, int24[] memory orderTicks) = _buildDeterministicOrders(key, isCurrency0, 3, 20e18);
        uint256 totalSize;
        for (uint256 i; i < orderSizes.length; ++i) {
            totalSize += orderSizes[i];
        }

        if (orderCoin == address(0)) {
            vm.deal(users.seller, totalSize);
        } else {
            deal(orderCoin, users.seller, totalSize);
            vm.startPrank(users.seller);
            IERC20(orderCoin).approve(address(limitOrderBook), totalSize);
            vm.stopPrank();
        }

        vm.recordLogs();
        vm.prank(users.seller);
        limitOrderBook.create{value: orderCoin == address(0) ? totalSize : 0}(key, isCurrency0, orderSizes, orderTicks, users.seller);
        CreatedOrderLog[] memory created = _decodeCreatedLogs(vm.getRecordedLogs());
        assertEq(created.length, orderSizes.length, "unexpected created order count");
        _assertOpenOrderState(users.seller, orderCoin, created[0].poolKeyHash, created, key.tickSpacing);

        // Move price past orders to make them fillable, but disable auto-fill so manual fill can consume them
        _movePriceBeyondTicksWithAutoFillDisabled(created);

        (int24 startTick, int24 endTick) = _tickWindow(created, key);
        bytes32 poolKeyHash = created[0].poolKeyHash;
        uint256 epochBefore = _poolEpoch(poolKeyHash);

        vm.recordLogs();
        limitOrderBook.fill(key, isCurrency0, startTick, endTick, 0, address(0));
        FilledOrderLog[] memory fills = _decodeFilledLogs(vm.getRecordedLogs());

        assertEq(fills.length, 2, "should fill router default count");

        uint256 expectedRemaining = totalSize;
        for (uint256 i; i < fills.length; ++i) {
            expectedRemaining -= uint256(fills[i].amountIn);
        }

        // Allow 1 wei rounding error due to liquidity/amount conversions in V4
        assertApproxEqAbs(_makerBalance(users.seller, orderCoin), expectedRemaining, 1, "maker balance");

        uint256 remainingTicks;
        for (uint256 i; i < created.length; ++i) {
            QueueSnapshot memory tickQueue = _tickQueueSnapshot(poolKeyHash, orderCoin, created[i].tick);
            if (tickQueue.length == 0) {
                assertEq(tickQueue.balance, 0, "cleared tick balance");
                assertFalse(_isTickInitialized(poolKeyHash, orderCoin, created[i].tick, key.tickSpacing), "tick bitmap still set");
            } else {
                ++remainingTicks;
                assertEq(tickQueue.length, 1, "remaining tick length");
                // Allow 1 wei rounding error due to liquidity/amount conversions in V4
                assertApproxEqAbs(uint256(tickQueue.balance), expectedRemaining, 1, "remaining tick balance");
            }
        }
        assertEq(remainingTicks, 1, "expected single remaining tick");

        _assertEpochIncrement(poolKeyHash, epochBefore);
    }

    function test_fillRangeRespectsExplicitMaxFillCount() public {
        PoolKey memory key = creatorCoin.getPoolKey();

        vm.recordLogs();
        _executeSingleHopSwapWithLimitOrders(users.buyer, key, DEFAULT_LIMIT_ORDER_AMOUNT, _defaultMultiples(), _defaultPercentages());
        CreatedOrderLog[] memory created = _decodeCreatedLogs(vm.getRecordedLogs());
        assertGt(created.length, 1, "expected multiple orders");
        _assertOpenOrderState(users.buyer, created[0].coin, created[0].poolKeyHash, created, key.tickSpacing);

        // Move price past orders so they are fully crossed
        _movePriceBeyondTicksWithAutoFillDisabled(created);

        (int24 startTick, int24 endTick) = _tickWindow(created, key);
        bool isCurrency0 = created[0].isCurrency0;
        bytes32 poolKeyHash = created[0].poolKeyHash;
        address orderCoin = created[0].coin;
        uint256 epochBefore = _poolEpoch(poolKeyHash);
        uint256 maxFillCount = 1;
        uint256 totalSize = _sumOrderSizes(created);

        vm.recordLogs();
        limitOrderBook.fill(key, isCurrency0, startTick, endTick, maxFillCount, address(0));
        FilledOrderLog[] memory fills = _decodeFilledLogs(vm.getRecordedLogs());

        assertEq(fills.length, maxFillCount, "fill count mismatch");

        uint256 expectedRemaining = totalSize;
        for (uint256 i; i < fills.length; ++i) {
            expectedRemaining -= uint256(fills[i].amountIn);
        }

        assertEq(_makerBalance(users.buyer, orderCoin), expectedRemaining, "maker balance");

        _assertEpochIncrement(poolKeyHash, epochBefore);
    }

    function test_manualFillWithDisabledHookAutoFill() public {
        PoolKey memory key = creatorCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(key.currency0) == address(creatorCoin);
        address orderCoin = _orderCoin(key, isCurrency0);

        // 1. Create a single manual order out-of-the-money
        (uint256[] memory orderSizes, int24[] memory orderTicks) = _buildDeterministicOrders(key, isCurrency0, 1, 50e18);
        uint256 totalSize = orderSizes[0];

        if (orderCoin == address(0)) {
            vm.deal(users.seller, totalSize);
        } else {
            deal(orderCoin, users.seller, totalSize);
            vm.prank(users.seller);
            IERC20(orderCoin).approve(address(limitOrderBook), totalSize);
        }

        vm.recordLogs();
        vm.prank(users.seller);
        limitOrderBook.create{value: orderCoin == address(0) ? totalSize : 0}(key, isCurrency0, orderSizes, orderTicks, users.seller);
        CreatedOrderLog[] memory created = _decodeCreatedLogs(vm.getRecordedLogs());
        assertEq(created.length, 1, "expected single order");

        bytes32 poolKeyHash = created[0].poolKeyHash;

        // 2. Do a small swap that DOESN'T cross the order to increment epoch
        //    (Order is far out of the money, so small swap won't reach it)
        address swapper = makeAddr("price-mover");
        uint128 smallSwap = uint128(DEFAULT_LIMIT_ORDER_AMOUNT / 100);
        deal(address(zoraToken), swapper, uint256(smallSwap));
        _swapSomeCurrencyForCoin(ICoin(address(creatorCoin)), address(zoraToken), smallSwap, swapper);

        // 3. Now DISABLE hook auto-fills
        uint256 originalMaxFillCount = limitOrderBook.getMaxFillCount();
        limitOrderBook.setMaxFillCount(0);

        // 4. Move price past the order WITHOUT triggering hook fills
        uint128 swapAmount = uint128(DEFAULT_LIMIT_ORDER_AMOUNT * 10);
        deal(address(zoraToken), swapper, uint256(swapAmount));
        _swapSomeCurrencyForCoin(ICoin(address(creatorCoin)), address(zoraToken), swapAmount, swapper);

        // 5. Restore original maxFillCount
        limitOrderBook.setMaxFillCount(originalMaxFillCount);

        // 6. Verify order exists and check epoch
        uint256 currentEpoch = _poolEpoch(poolKeyHash);
        QueueSnapshot memory queueBefore = _tickQueueSnapshot(poolKeyHash, orderCoin, created[0].tick);
        assertGt(queueBefore.length, 0, "order should exist in tick queue");

        // Note: we created at epoch 0, small swap incremented to 1, big swap tried to fill but maxFillCount=0
        // So current epoch should be > 0, allowing our fill

        // 7. Now manually fill the order with explicit tick window
        uint256 epochBefore = currentEpoch;
        (int24 startTick, int24 endTick) = _tickWindow(created, key);

        vm.recordLogs();
        limitOrderBook.fill(key, isCurrency0, startTick, endTick, 1, address(0));
        FilledOrderLog[] memory fills = _decodeFilledLogs(vm.getRecordedLogs());

        // 8. Verify fill succeeded
        assertEq(fills.length, 1, "should fill single order");
        assertEq(fills[0].maker, users.seller, "maker mismatch");
        assertGt(fills[0].amountOut, 0, "should have output amount");

        _assertEpochIncrement(poolKeyHash, epochBefore);

        // Verify order consumed
        QueueSnapshot memory tickQueue = _tickQueueSnapshot(poolKeyHash, orderCoin, created[0].tick);
        assertEq(tickQueue.length, 0, "tick queue should be empty");
        assertEq(tickQueue.balance, 0, "tick balance should be zero");
    }

    function test_fillRangePaysReferral() public {
        PoolKey memory key = creatorCoin.getPoolKey();
        address referral = makeAddr("referral");

        // 1. Create orders via swap - orders placed as limit orders behind current price
        vm.recordLogs();
        _executeSingleHopSwapWithLimitOrders(users.buyer, key, DEFAULT_LIMIT_ORDER_AMOUNT, _defaultMultiples(), _defaultPercentages());
        CreatedOrderLog[] memory created = _decodeCreatedLogs(vm.getRecordedLogs());
        assertGt(created.length, 0, "expected orders to be created");
        _assertOpenOrderState(users.buyer, created[0].coin, created[0].poolKeyHash, created, key.tickSpacing);

        // Move price past orders so they are fully crossed
        _movePriceBeyondTicksWithAutoFillDisabled(created);

        bool isCurrency0 = created[0].isCurrency0;
        address orderCoin = created[0].coin;
        bytes32 poolKeyHash = created[0].poolKeyHash;

        // 2. Fill one order with referral address
        (int24 startTick, int24 endTick) = _tickWindow(created, key);
        address payoutCoin = isCurrency0 ? Currency.unwrap(key.currency1) : Currency.unwrap(key.currency0);
        uint256 referralBalanceBefore = _balanceOf(payoutCoin, referral);
        uint256 epochBefore = _poolEpoch(poolKeyHash);

        vm.recordLogs();
        limitOrderBook.fill(key, isCurrency0, startTick, endTick, 1, referral);
        FilledOrderLog[] memory fills = _decodeFilledLogs(vm.getRecordedLogs());

        assertEq(fills.length, 1, "should fill single order");
        assertEq(fills[0].maker, users.buyer, "maker mismatch");
        assertEq(fills[0].coinIn, orderCoin, "coin mismatch");
        assertEq(fills[0].fillReferral, referral, "referral address is correctly tracked");

        // Verify referral balance change matches the event amount (validates accounting correctness)
        uint256 referralBalanceAfter = _balanceOf(payoutCoin, referral);
        uint256 referralDelta = referralBalanceAfter - referralBalanceBefore;
        assertEq(referralDelta, fills[0].fillReferralAmount, "referral balance delta must match event");

        _assertEpochIncrement(poolKeyHash, epochBefore);
    }

    function test_fillRevertsOnInvalidWindowCurrency0() public {
        PoolKey memory key = creatorCoin.getPoolKey();
        int24 baseTick = _alignedTick(_currentTick(key), key.tickSpacing);
        int24 startTick = baseTick + key.tickSpacing;
        int24 endTick = baseTick - key.tickSpacing;

        vm.expectRevert(abi.encodeWithSelector(IZoraLimitOrderBook.InvalidFillWindow.selector, startTick, endTick, true));
        limitOrderBook.fill(key, true, startTick, endTick, 1, address(0));
    }

    function test_fillRevertsOnInvalidWindowCurrency1() public {
        PoolKey memory key = creatorCoin.getPoolKey();
        int24 baseTick = _alignedTick(_currentTick(key), key.tickSpacing);
        int24 startTick = baseTick - key.tickSpacing;
        int24 endTick = baseTick + key.tickSpacing;

        vm.expectRevert(abi.encodeWithSelector(IZoraLimitOrderBook.InvalidFillWindow.selector, startTick, endTick, false));
        limitOrderBook.fill(key, false, startTick, endTick, 1, address(0));
    }

    function test_fillRangeViaHookConsumesOrders() public {
        PoolKey memory key = creatorCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(key.currency0) == address(creatorCoin);
        address orderCoin = _orderCoin(key, isCurrency0);

        // Create orders manually at specific ticks OUT of the money
        (uint256[] memory orderSizes, int24[] memory orderTicks) = _buildDeterministicOrders(key, isCurrency0, 3, 30e18);
        uint256 totalSize;
        for (uint256 i = 0; i < orderSizes.length; ++i) {
            totalSize += orderSizes[i];
        }

        _fundMaker(orderCoin, users.seller, totalSize);

        vm.recordLogs();
        vm.prank(users.seller);
        limitOrderBook.create{value: orderCoin == address(0) ? totalSize : 0}(key, isCurrency0, orderSizes, orderTicks, users.seller);
        CreatedOrderLog[] memory created = _decodeCreatedLogs(vm.getRecordedLogs());
        assertEq(created.length, orderSizes.length, "expected all orders to be created");
        _assertOpenOrderState(users.seller, orderCoin, created[0].poolKeyHash, created, key.tickSpacing);

        bytes32 poolKeyHash = created[0].poolKeyHash;
        uint256 epochBefore = _poolEpoch(poolKeyHash);

        // _movePriceBeyondTicks triggers the hook's afterSwap which automatically fills the orders
        vm.recordLogs();
        _movePriceBeyondTicks(created);
        FilledOrderLog[] memory fills = _decodeFilledLogs(vm.getRecordedLogs());

        assertEq(fills.length, created.length, "hook fill count mismatch");
        assertEq(_makerBalance(users.seller, orderCoin), 0, "maker balance should clear");
        _assertEpochIncrement(poolKeyHash, epochBefore);
    }

    function test_fillRangeSkipsStaleOrdersButRespectsMaxFillCount() public {
        PoolKey memory key = creatorCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(key.currency0) == address(creatorCoin);
        address orderCoin = _orderCoin(key, isCurrency0);

        (uint256[] memory orderSizes, int24[] memory orderTicks) = _buildDeterministicOrders(key, isCurrency0, 3, 25e18);
        uint256 totalSize;
        for (uint256 i; i < orderSizes.length; ++i) {
            totalSize += orderSizes[i];
        }

        if (orderCoin == address(0)) {
            vm.deal(users.seller, totalSize);
        } else {
            deal(orderCoin, users.seller, totalSize);
            vm.startPrank(users.seller);
            IERC20(orderCoin).approve(address(limitOrderBook), totalSize);
            vm.stopPrank();
        }

        vm.recordLogs();
        vm.prank(users.seller);
        limitOrderBook.create{value: orderCoin == address(0) ? totalSize : 0}(key, isCurrency0, orderSizes, orderTicks, users.seller);
        CreatedOrderLog[] memory created = _decodeCreatedLogs(vm.getRecordedLogs());
        assertEq(created.length, orderSizes.length, "unexpected created order count");
        _assertOpenOrderState(users.seller, orderCoin, created[0].poolKeyHash, created, key.tickSpacing);

        bytes32 poolKeyHash = created[0].poolKeyHash;
        uint256 epochBefore = _poolEpoch(poolKeyHash);

        uint256 staleIndex;
        int24 minTick = created[0].tick;
        for (uint256 i = 1; i < created.length; ++i) {
            if (created[i].tick < minTick) {
                minTick = created[i].tick;
                staleIndex = i;
            }
        }
        _setOrderCreatedEpoch(created[staleIndex].orderId, uint32(epochBefore + 1));

        _movePriceBeyondTicksWithAutoFillDisabled(created);

        (int24 startTick, int24 endTick) = _tickWindow(created, key);
        uint256 maxFillCount = 2;

        vm.recordLogs();
        limitOrderBook.fill(key, isCurrency0, startTick, endTick, maxFillCount, address(0));
        FilledOrderLog[] memory fills = _decodeFilledLogs(vm.getRecordedLogs());

        assertEq(fills.length, maxFillCount, "fill count mismatch");
        for (uint256 i; i < fills.length; ++i) {
            assertTrue(fills[i].orderId != created[staleIndex].orderId, "stale order should remain");
        }

        uint256 expectedRemaining = totalSize;
        for (uint256 i; i < fills.length; ++i) {
            expectedRemaining -= uint256(fills[i].amountIn);
        }

        assertEq(_makerBalance(users.seller, orderCoin), expectedRemaining, "maker balance");

        for (uint256 i; i < created.length; ++i) {
            QueueSnapshot memory tickQueue = _tickQueueSnapshot(poolKeyHash, orderCoin, created[i].tick);
            if (i == staleIndex) {
                assertEq(tickQueue.length, 1, "stale tick length");
                assertEq(uint256(tickQueue.balance), expectedRemaining, "stale tick balance");
                assertTrue(_isTickInitialized(poolKeyHash, orderCoin, created[i].tick, key.tickSpacing), "stale tick bitmap cleared");
            } else {
                assertEq(tickQueue.length, 0, "cleared tick length");
                assertEq(tickQueue.balance, 0, "cleared tick balance");
                assertFalse(_isTickInitialized(poolKeyHash, orderCoin, created[i].tick, key.tickSpacing), "tick bitmap still set");
            }
        }

        _assertEpochIncrement(poolKeyHash, epochBefore);
    }

    function test_fillBatchConsumesOrders() public {
        PoolKey memory key = creatorCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(key.currency0) == address(creatorCoin);
        address orderCoin = LimitOrderCommon.getOrderCoin(key, isCurrency0);

        (uint256[] memory orderSizes, int24[] memory orderTicks) = _buildDeterministicOrders(key, isCurrency0, 2, 25e18);
        uint256 totalSize;
        for (uint256 i; i < orderSizes.length; ++i) {
            totalSize += orderSizes[i];
        }
        if (orderCoin == address(0)) {
            vm.deal(users.seller, totalSize);
        } else {
            deal(orderCoin, users.seller, totalSize);
            vm.prank(users.seller);
            IERC20(orderCoin).approve(address(limitOrderBook), totalSize);
        }

        vm.recordLogs();
        vm.prank(users.seller);
        bytes32[] memory orderIds = limitOrderBook.create{value: orderCoin == address(0) ? totalSize : 0}(
            key,
            isCurrency0,
            orderSizes,
            orderTicks,
            users.seller
        );
        assertTrue(orderIds[0] != orderIds[1], "duplicate order ids");
        LimitOrderTypes.LimitOrder memory order0Before = limitOrderBook.exposedOrder(orderIds[0]);
        LimitOrderTypes.LimitOrder memory order1Before = limitOrderBook.exposedOrder(orderIds[1]);
        assertEq(uint256(order0Before.status), uint256(LimitOrderTypes.OrderStatus.OPEN), "order0 pre status");
        assertEq(uint256(order1Before.status), uint256(LimitOrderTypes.OrderStatus.OPEN), "order1 pre status");

        CreatedOrderLog[] memory created = _decodeCreatedLogs(vm.getRecordedLogs());
        assertEq(created.length, orderIds.length, "unexpected created order count");
        bytes32 poolKeyHash = CoinCommon.hashPoolKey(key);
        for (uint256 i; i < created.length; ++i) {
            assertEq(created[i].poolKeyHash, poolKeyHash, "pool hash mismatch");
        }
        _assertOpenOrderState(users.seller, orderCoin, poolKeyHash, created, key.tickSpacing);

        _movePriceBeyondTicks(created);

        IZoraLimitOrderBook.OrderBatch[] memory batches = new IZoraLimitOrderBook.OrderBatch[](1);
        batches[0] = IZoraLimitOrderBook.OrderBatch({key: key, isCurrency0: isCurrency0, orderIds: orderIds});

        limitOrderBook.fill(batches, address(0));
        LimitOrderTypes.LimitOrder memory order0After = limitOrderBook.exposedOrder(orderIds[0]);
        LimitOrderTypes.LimitOrder memory order1After = limitOrderBook.exposedOrder(orderIds[1]);
        assertEq(uint256(order0After.status), uint256(LimitOrderTypes.OrderStatus.FILLED), "order0 post status");
        assertEq(uint256(order1After.status), uint256(LimitOrderTypes.OrderStatus.FILLED), "order1 post status");
        assertEq(_makerBalance(users.seller, orderCoin), 0, "maker balance should be zero");

        for (uint256 i; i < created.length; ++i) {
            QueueSnapshot memory tickQueue = _tickQueueSnapshot(created[i].poolKeyHash, orderCoin, created[i].tick);
            assertEq(tickQueue.length, 0, "tick queue length");
            assertEq(tickQueue.balance, 0, "tick queue balance");
            assertFalse(_isTickInitialized(created[i].poolKeyHash, orderCoin, created[i].tick, key.tickSpacing), "tick bitmap still set");
        }
    }

    function test_fillBatchConsumesOrdersWithAutoFillDisabledDuringSetup() public {
        PoolKey memory key = creatorCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(key.currency0) == address(creatorCoin);
        address orderCoin = LimitOrderCommon.getOrderCoin(key, isCurrency0);

        (uint256[] memory orderSizes, int24[] memory orderTicks) = _buildDeterministicOrders(key, isCurrency0, 2, 25e18);
        uint256 totalSize;
        for (uint256 i; i < orderSizes.length; ++i) {
            totalSize += orderSizes[i];
        }
        if (orderCoin == address(0)) {
            vm.deal(users.seller, totalSize);
        } else {
            deal(orderCoin, users.seller, totalSize);
            vm.prank(users.seller);
            IERC20(orderCoin).approve(address(limitOrderBook), totalSize);
        }

        vm.recordLogs();
        vm.prank(users.seller);
        bytes32[] memory orderIds = limitOrderBook.create{value: orderCoin == address(0) ? totalSize : 0}(
            key,
            isCurrency0,
            orderSizes,
            orderTicks,
            users.seller
        );

        CreatedOrderLog[] memory created = _decodeCreatedLogs(vm.getRecordedLogs());
        assertEq(created.length, orderIds.length, "unexpected created order count");

        _movePriceBeyondTicksWithAutoFillDisabled(created);

        IZoraLimitOrderBook.OrderBatch[] memory batches = new IZoraLimitOrderBook.OrderBatch[](1);
        batches[0] = IZoraLimitOrderBook.OrderBatch({key: key, isCurrency0: isCurrency0, orderIds: orderIds});

        limitOrderBook.fill(batches, address(0));
        LimitOrderTypes.LimitOrder memory order0After = limitOrderBook.exposedOrder(orderIds[0]);
        LimitOrderTypes.LimitOrder memory order1After = limitOrderBook.exposedOrder(orderIds[1]);
        assertEq(uint256(order0After.status), uint256(LimitOrderTypes.OrderStatus.FILLED), "order0 post status");
        assertEq(uint256(order1After.status), uint256(LimitOrderTypes.OrderStatus.FILLED), "order1 post status");
        assertEq(_makerBalance(users.seller, orderCoin), 0, "maker balance should be zero");
    }

    function _balanceOf(address token, address account) private view returns (uint256) {
        if (token == address(0)) {
            return account.balance;
        }
        return IERC20(token).balanceOf(account);
    }

    function _fundMaker(address asset, address maker, uint256 amount) private {
        if (asset == address(0)) {
            vm.deal(maker, amount);
        } else {
            deal(asset, maker, amount);
            vm.prank(maker);
            IERC20(asset).approve(address(limitOrderBook), amount);
        }
    }

    function test_fillWithNoResidual() public {
        PoolKey memory key = creatorCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(key.currency0) == address(creatorCoin);
        address orderCoin = _orderCoin(key, isCurrency0);

        // Create orders with sizes that divide evenly into liquidity (no residual)
        (uint256[] memory orderSizes, int24[] memory orderTicks) = _buildDeterministicOrders(key, isCurrency0, 1, 100e18);

        uint256 totalSize = orderSizes[0];
        _fundAndApprove(users.seller, orderCoin, totalSize);

        vm.recordLogs();
        vm.prank(users.seller);
        limitOrderBook.create{value: orderCoin == address(0) ? totalSize : 0}(key, isCurrency0, orderSizes, orderTicks, users.seller);

        CreatedOrderLog[] memory created = _decodeCreatedLogs(vm.getRecordedLogs());
        _movePriceBeyondTicksWithAutoFillDisabled(created);

        // Fill order - should handle zero residual gracefully
        (int24 startTick, int24 endTick) = _tickWindow(created, key);
        vm.recordLogs();
        limitOrderBook.fill(key, isCurrency0, startTick, endTick, created.length, address(0));

        FilledOrderLog[] memory fills = _decodeFilledLogs(vm.getRecordedLogs());
        assertEq(fills.length, 1, "should fill one order");
    }

    function test_fillWithReferral() public {
        PoolKey memory key = creatorCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(key.currency0) == address(creatorCoin);
        address orderCoin = _orderCoin(key, isCurrency0);

        (uint256[] memory orderSizes, int24[] memory orderTicks) = _buildDeterministicOrders(key, isCurrency0, 1, 50e18);

        uint256 totalSize = orderSizes[0];
        _fundAndApprove(users.seller, orderCoin, totalSize);

        vm.recordLogs();
        vm.prank(users.seller);
        limitOrderBook.create{value: orderCoin == address(0) ? totalSize : 0}(key, isCurrency0, orderSizes, orderTicks, users.seller);

        CreatedOrderLog[] memory created = _decodeCreatedLogs(vm.getRecordedLogs());
        _movePriceBeyondTicksWithAutoFillDisabled(created);

        // Fill with referral address
        address referral = makeAddr("referral");
        (int24 startTick, int24 endTick) = _tickWindow(created, key);

        vm.recordLogs();
        limitOrderBook.fill(key, isCurrency0, startTick, endTick, created.length, referral);

        FilledOrderLog[] memory fills = _decodeFilledLogs(vm.getRecordedLogs());
        assertEq(fills.length, 1, "should fill one order");
        assertEq(fills[0].fillReferral, referral, "referral should be set");
        assertGt(fills[0].fillReferralAmount, 0, "referral should receive fee");
    }

    function test_fillWithoutReferral() public {
        PoolKey memory key = creatorCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(key.currency0) == address(creatorCoin);
        address orderCoin = _orderCoin(key, isCurrency0);

        (uint256[] memory orderSizes, int24[] memory orderTicks) = _buildDeterministicOrders(key, isCurrency0, 1, 50e18);

        uint256 totalSize = orderSizes[0];
        _fundAndApprove(users.seller, orderCoin, totalSize);

        vm.recordLogs();
        vm.prank(users.seller);
        limitOrderBook.create{value: orderCoin == address(0) ? totalSize : 0}(key, isCurrency0, orderSizes, orderTicks, users.seller);

        CreatedOrderLog[] memory created = _decodeCreatedLogs(vm.getRecordedLogs());
        _movePriceBeyondTicksWithAutoFillDisabled(created);

        // Fill without referral (address(0))
        (int24 startTick, int24 endTick) = _tickWindow(created, key);

        vm.recordLogs();
        limitOrderBook.fill(key, isCurrency0, startTick, endTick, created.length, address(0));

        FilledOrderLog[] memory fills = _decodeFilledLogs(vm.getRecordedLogs());
        assertEq(fills.length, 1, "should fill one order");
        assertEq(fills[0].fillReferral, address(0), "referral should be zero");
        assertEq(fills[0].fillReferralAmount, 0, "referral should receive no fee");
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

    /// @notice Tests fill() with maxFillCount=0 (line 86-88)
    /// @dev This tests the branch: if (maxFillCount == 0) maxFillCount = getMaxFillCount();
    function test_fill_maxFillCountZero_usesDefault() public {
        PoolKey memory key = creatorCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(key.currency0) == address(creatorCoin);
        address orderCoin = _orderCoin(key, isCurrency0);

        // Set max fill count to 2 so we can verify default is used
        limitOrderBook.setMaxFillCount(2);

        // Create 5 orders that can be filled
        (uint256[] memory orderSizes, int24[] memory orderTicks) = _buildDeterministicOrders(key, isCurrency0, 5, 20e18);
        uint256 totalSize;
        for (uint256 i; i < orderSizes.length; ++i) {
            totalSize += orderSizes[i];
        }

        if (orderCoin == address(0)) {
            vm.deal(users.seller, totalSize);
        } else {
            deal(orderCoin, users.seller, totalSize);
            vm.startPrank(users.seller);
            IERC20(orderCoin).approve(address(limitOrderBook), totalSize);
            vm.stopPrank();
        }

        vm.recordLogs();
        vm.prank(users.seller);
        limitOrderBook.create{value: orderCoin == address(0) ? totalSize : 0}(key, isCurrency0, orderSizes, orderTicks, users.seller);
        CreatedOrderLog[] memory created = _decodeCreatedLogs(vm.getRecordedLogs());
        assertEq(created.length, orderSizes.length, "unexpected created order count");

        // Move price past orders to make them fillable, but disable auto-fill so manual fill can consume them
        _movePriceBeyondTicksWithAutoFillDisabled(created);

        (int24 startTick, int24 endTick) = _tickWindow(created, key);

        // Call fill with maxFillCount = 0 (should use default of 2)
        vm.recordLogs();
        limitOrderBook.fill(key, isCurrency0, startTick, endTick, 0, address(0));
        FilledOrderLog[] memory fills = _decodeFilledLogs(vm.getRecordedLogs());

        // Should fill 2 orders (the default max count)
        assertEq(fills.length, 2, "should fill default max count of 2 orders");
    }

    /// @notice Tests fill() caps maxFillCount to configured default
    function test_fill_maxFillCountExceedsDefault_isCapped() public {
        PoolKey memory key = creatorCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(key.currency0) == address(creatorCoin);
        address orderCoin = _orderCoin(key, isCurrency0);

        // Set max fill count to 2
        limitOrderBook.setMaxFillCount(2);

        // Create 5 fillable orders
        (uint256[] memory orderSizes, int24[] memory orderTicks) = _buildDeterministicOrders(key, isCurrency0, 5, 20e18);
        uint256 totalSize;
        for (uint256 i; i < orderSizes.length; ++i) {
            totalSize += orderSizes[i];
        }

        if (orderCoin == address(0)) {
            vm.deal(users.seller, totalSize);
        } else {
            deal(orderCoin, users.seller, totalSize);
            vm.startPrank(users.seller);
            IERC20(orderCoin).approve(address(limitOrderBook), totalSize);
            vm.stopPrank();
        }

        vm.recordLogs();
        vm.prank(users.seller);
        limitOrderBook.create{value: orderCoin == address(0) ? totalSize : 0}(key, isCurrency0, orderSizes, orderTicks, users.seller);
        CreatedOrderLog[] memory created = _decodeCreatedLogs(vm.getRecordedLogs());

        _movePriceBeyondTicksWithAutoFillDisabled(created);
        (int24 startTick, int24 endTick) = _tickWindow(created, key);

        // Call fill with maxFillCount = 100 (way above default of 2)
        vm.recordLogs();
        limitOrderBook.fill(key, isCurrency0, startTick, endTick, 100, address(0));
        FilledOrderLog[] memory fills = _decodeFilledLogs(vm.getRecordedLogs());

        // Should cap to 2 orders (the configured max)
        assertEq(fills.length, 2, "should cap to configured max of 2 orders");
    }

    /// @notice Tests batch fill with empty orderIds array (line 134)
    /// @dev This tests the branch: if (batch.orderIds.length != 0)
    function test_batchFill_emptyOrderIds_skips() public {
        PoolKey memory key = creatorCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(key.currency0) == address(creatorCoin);

        // Create batch with empty orderIds
        IZoraLimitOrderBook.OrderBatch[] memory batches = new IZoraLimitOrderBook.OrderBatch[](2);
        batches[0] = IZoraLimitOrderBook.OrderBatch({
            key: key,
            isCurrency0: isCurrency0,
            orderIds: new bytes32[](0) // Empty array - should be skipped
        });
        batches[1] = IZoraLimitOrderBook.OrderBatch({
            key: key,
            isCurrency0: isCurrency0,
            orderIds: new bytes32[](0) // Empty array - should be skipped
        });

        vm.recordLogs();
        limitOrderBook.fill(batches, address(0));

        // Should complete without reverting (skips empty batches)
        FilledOrderLog[] memory fills = _decodeFilledLogs(vm.getRecordedLogs());
        assertEq(fills.length, 0, "should not fill anything from empty batches");
    }

    /// @notice Tests batch fill with mixed empty and non-empty batches
    function test_batchFill_mixedEmptyAndNonEmpty_processesNonEmpty() public {
        PoolKey memory key = creatorCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(key.currency0) == address(creatorCoin);
        address orderCoin = _orderCoin(key, isCurrency0);

        // Create one order
        (uint256[] memory orderSizes, int24[] memory orderTicks) = _buildDeterministicOrders(key, isCurrency0, 1, 25e18);
        uint256 totalSize = orderSizes[0];

        if (orderCoin == address(0)) {
            vm.deal(users.seller, totalSize);
        } else {
            deal(orderCoin, users.seller, totalSize);
            vm.startPrank(users.seller);
            IERC20(orderCoin).approve(address(limitOrderBook), totalSize);
            vm.stopPrank();
        }

        vm.recordLogs();
        vm.prank(users.seller);
        limitOrderBook.create{value: orderCoin == address(0) ? totalSize : 0}(key, isCurrency0, orderSizes, orderTicks, users.seller);
        CreatedOrderLog[] memory created = _decodeCreatedLogs(vm.getRecordedLogs());
        assertEq(created.length, 1, "should create 1 order");

        // Move price past order to make it fillable, with auto-fill disabled
        _movePriceBeyondTicksWithAutoFillDisabled(created);

        // Create batches: first empty, second with order
        IZoraLimitOrderBook.OrderBatch[] memory batches = new IZoraLimitOrderBook.OrderBatch[](2);
        batches[0] = IZoraLimitOrderBook.OrderBatch({
            key: key,
            isCurrency0: isCurrency0,
            orderIds: new bytes32[](0) // Empty - should skip
        });

        bytes32[] memory orderIds = new bytes32[](1);
        orderIds[0] = created[0].orderId;
        batches[1] = IZoraLimitOrderBook.OrderBatch({
            key: key,
            isCurrency0: isCurrency0,
            orderIds: orderIds // Non-empty - should process
        });

        vm.recordLogs();
        limitOrderBook.fill(batches, address(0));

        FilledOrderLog[] memory fills = _decodeFilledLogs(vm.getRecordedLogs());
        assertEq(fills.length, 1, "should fill the one order from non-empty batch");
    }

    /// @notice Verifies that once the pool tick crosses past the order boundary, the order
    ///         gets filled and coinOut is the counter asset (not same as coinIn).
    function test_fillSucceedsOnceCrossed_rangeWalk() public {
        PoolKey memory key = creatorCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(key.currency0) == address(creatorCoin);
        address orderCoin = _orderCoin(key, isCurrency0);

        // Create a single order out-of-the-money
        (uint256[] memory orderSizes, int24[] memory orderTicks) = _buildDeterministicOrders(key, isCurrency0, 1, 50e18);
        uint256 totalSize = orderSizes[0];
        _fundAndApprove(users.seller, orderCoin, totalSize);

        vm.recordLogs();
        vm.prank(users.seller);
        limitOrderBook.create{value: orderCoin == address(0) ? totalSize : 0}(key, isCurrency0, orderSizes, orderTicks, users.seller);
        CreatedOrderLog[] memory created = _decodeCreatedLogs(vm.getRecordedLogs());

        bytes32 orderId = created[0].orderId;

        // Move price past the order to make it crossed (using real swap, auto-fill disabled)
        _movePriceBeyondTicksWithAutoFillDisabled(created);

        // Now fill manually - should work since order is crossed
        (int24 startTick, int24 endTick) = _tickWindow(created, key);
        vm.recordLogs();
        limitOrderBook.fill(key, isCurrency0, startTick, endTick, 10, address(0));
        FilledOrderLog[] memory fills = _decodeFilledLogs(vm.getRecordedLogs());

        // Should fill
        assertEq(fills.length, 1, "should fill after crossing");

        // Verify coinIn != coinOut (counter asset received)
        assertTrue(fills[0].coinIn != fills[0].coinOut, "coinIn should differ from coinOut");
        assertEq(fills[0].coinIn, orderCoin, "coinIn should be the order coin");
        assertGt(fills[0].amountOut, 0, "should have non-zero amountOut");

        // Verify order is now FILLED
        LimitOrderTypes.LimitOrder memory orderAfter = limitOrderBook.exposedOrder(orderId);
        assertEq(uint256(orderAfter.status), uint256(LimitOrderTypes.OrderStatus.FILLED), "order should be FILLED");
    }

    /// @notice Same as above but using the batch fill path.
    function test_fillSucceedsOnceCrossed_batchFill() public {
        PoolKey memory key = creatorCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(key.currency0) == address(creatorCoin);
        address orderCoin = _orderCoin(key, isCurrency0);

        // Create a single order out-of-the-money
        (uint256[] memory orderSizes, int24[] memory orderTicks) = _buildDeterministicOrders(key, isCurrency0, 1, 50e18);
        uint256 totalSize = orderSizes[0];
        _fundAndApprove(users.seller, orderCoin, totalSize);

        vm.recordLogs();
        vm.prank(users.seller);
        bytes32[] memory orderIds = limitOrderBook.create{value: orderCoin == address(0) ? totalSize : 0}(
            key,
            isCurrency0,
            orderSizes,
            orderTicks,
            users.seller
        );
        CreatedOrderLog[] memory created = _decodeCreatedLogs(vm.getRecordedLogs());

        // Move price past the order to make it crossed
        _movePriceBeyondTicksWithAutoFillDisabled(created);

        // Fill via batch - should work since order is crossed
        IZoraLimitOrderBook.OrderBatch[] memory batches = new IZoraLimitOrderBook.OrderBatch[](1);
        batches[0] = IZoraLimitOrderBook.OrderBatch({key: key, isCurrency0: isCurrency0, orderIds: orderIds});

        vm.recordLogs();
        limitOrderBook.fill(batches, address(0));
        FilledOrderLog[] memory fills = _decodeFilledLogs(vm.getRecordedLogs());

        // Should fill
        assertEq(fills.length, 1, "should fill after crossing via batch");
        assertTrue(fills[0].coinIn != fills[0].coinOut, "coinIn should differ from coinOut");
    }

    /// @notice Tests that after crossing, fill correctly pays out the counter asset.
    ///         This is a simpler version that just verifies correct payout after real price movement.
    function test_fillAfterCrossing_correctPayout() public {
        PoolKey memory key = creatorCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(key.currency0) == address(creatorCoin);
        address orderCoin = _orderCoin(key, isCurrency0);
        address counterCoin = isCurrency0 ? Currency.unwrap(key.currency1) : Currency.unwrap(key.currency0);

        (uint256[] memory orderSizes, int24[] memory orderTicks) = _buildDeterministicOrders(key, isCurrency0, 1, 50e18);
        uint256 totalSize = orderSizes[0];
        _fundAndApprove(users.seller, orderCoin, totalSize);

        vm.recordLogs();
        vm.prank(users.seller);
        limitOrderBook.create{value: orderCoin == address(0) ? totalSize : 0}(key, isCurrency0, orderSizes, orderTicks, users.seller);
        CreatedOrderLog[] memory created = _decodeCreatedLogs(vm.getRecordedLogs());

        // Move price past the order
        _movePriceBeyondTicksWithAutoFillDisabled(created);

        // Fill
        (int24 startTick, int24 endTick) = _tickWindow(created, key);
        vm.recordLogs();
        limitOrderBook.fill(key, isCurrency0, startTick, endTick, 10, address(0));
        FilledOrderLog[] memory fills = _decodeFilledLogs(vm.getRecordedLogs());

        assertEq(fills.length, 1, "should fill");
        assertEq(fills[0].coinIn, orderCoin, "coinIn should be order coin");
        assertEq(fills[0].coinOut, counterCoin, "coinOut should be counter coin");
        assertGt(fills[0].amountOut, 0, "should receive counter asset");
    }
}
