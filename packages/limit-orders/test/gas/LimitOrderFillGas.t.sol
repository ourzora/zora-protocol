// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {BaseTest} from "../utils/BaseTest.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {LimitOrderCommon} from "../../src/libs/LimitOrderCommon.sol";

/**
 * @title LimitOrderFillGasTest
 * @notice Gas benchmark tests for limit order fill operations with payout swaps
 * @dev Tests are structured to capture:
 *      1. Baseline swap without limit orders
 *      2. Single-hop fill (direct payout)
 *      3. Multi-hop fill (with intermediate swaps triggering hook recursion)
 *      4. Multi-order fill (5 orders with multi-hop payouts)
 */
contract LimitOrderFillGasTest is BaseTest {
    // Gas measurement helpers
    uint256 private gasStart;
    uint256 private gasUsed;

    function setUp() public virtual override {
        super.setUp();
        // Ensure maxFillCount is set to a reasonable value
        limitOrderBook.setMaxFillCount(50);
    }

    /// @notice Test 1: Baseline swap without limit orders to establish control measurement
    /// @dev This provides a baseline for comparing hook costs with and without sender check
    function test_gas_baseline_swap_no_limit_orders() public {
        PoolKey memory key = creatorCoin.getPoolKey();
        uint256 swapAmount = 10e18;

        // Execute swap via the standard test helper and measure gas
        gasStart = gasleft();
        _executeSingleHopSwap(users.buyer, swapAmount, key, bytes(""));
        gasUsed = gasStart - gasleft();

        // Log result for comparison
        emit log_named_uint("BASELINE_SWAP_GAS", gasUsed);
    }

    /// @notice Test 2: Single order fill with direct payout (0-hop - no conversion)
    /// @dev Measures gas when filling one limit order that pays out directly without swap path
    function test_gas_0hop_single_order_direct_payout() public {
        PoolKey memory key = creatorCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(key.currency0) == address(creatorCoin);
        address orderCoin = LimitOrderCommon.getOrderCoin(key, isCurrency0);

        // Create a single limit order
        uint256 orderSize = 25e18;
        (uint256[] memory orderSizes, int24[] memory orderTicks) = _buildDeterministicOrders(key, isCurrency0, 1, orderSize);

        // Fund maker
        if (orderCoin == address(0)) {
            vm.deal(users.seller, orderSize);
        } else {
            deal(orderCoin, users.seller, orderSize);
            vm.prank(users.seller);
            IERC20(orderCoin).approve(address(limitOrderBook), orderSize);
        }

        // Create order
        vm.recordLogs();
        vm.prank(users.seller);
        limitOrderBook.create{value: orderCoin == address(0) ? orderSize : 0}(key, isCurrency0, orderSizes, orderTicks, users.seller);
        CreatedOrderLog[] memory created = _decodeCreatedLogs(vm.getRecordedLogs());
        require(created.length == 1, "Expected 1 order");

        // Move price to make order fillable (without triggering auto-fill)
        _movePriceBeyondTicksWithAutoFillDisabled(created);

        // Fill order and measure gas
        (int24 startTick, int24 endTick) = _tickWindow(created, key);
        gasStart = gasleft();
        limitOrderBook.fill(key, isCurrency0, startTick, endTick, 1, address(0));
        gasUsed = gasStart - gasleft();

        emit log_named_uint("SINGLE_ORDER_DIRECT_PAYOUT_GAS", gasUsed);
    }

    /// @notice Test 3: Single order fill with 2-hop payout (content → creator → ZORA)
    /// @dev Measures gas for the 2-hop conversion path using contentCoin which converts through creatorCoin to ZORA
    function test_gas_2hop_single_order_fill() public {
        // Use contentCoin which has a swap path to creatorCoin
        PoolKey memory contentKey = contentCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(contentKey.currency0) == address(contentCoin);
        address orderCoin = LimitOrderCommon.getOrderCoin(contentKey, isCurrency0);

        // Create a single limit order on contentCoin pool
        uint256 orderSize = 25e18;
        (uint256[] memory orderSizes, int24[] memory orderTicks) = _buildDeterministicOrders(contentKey, isCurrency0, 1, orderSize);

        // Fund maker
        if (orderCoin == address(0)) {
            vm.deal(users.seller, orderSize);
        } else {
            deal(orderCoin, users.seller, orderSize);
            vm.prank(users.seller);
            IERC20(orderCoin).approve(address(limitOrderBook), orderSize);
        }

        // Create order
        vm.recordLogs();
        vm.prank(users.seller);
        limitOrderBook.create{value: orderCoin == address(0) ? orderSize : 0}(contentKey, isCurrency0, orderSizes, orderTicks, users.seller);
        CreatedOrderLog[] memory created = _decodeCreatedLogs(vm.getRecordedLogs());
        require(created.length == 1, "Expected 1 order");

        // Move price to make order fillable
        _movePriceBeyondTicksWithAutoFillDisabled(created);

        // Fill order - this will trigger swap path with intermediate swaps
        // Each intermediate swap hits ZoraV4CoinHook._afterSwap() causing:
        // - Fee collection
        // - LP reward distribution
        // - Referral tracking
        // - Epoch updates
        (int24 startTick, int24 endTick) = _tickWindow(created, contentKey);
        gasStart = gasleft();
        limitOrderBook.fill(contentKey, isCurrency0, startTick, endTick, 1, address(0));
        gasUsed = gasStart - gasleft();

        emit log_named_uint("SINGLE_ORDER_MULTIHOP_PAYOUT_GAS", gasUsed);
    }

    /// @notice Test 4: Fill 5 orders with 2-hop payouts (content → creator → ZORA)
    /// @dev Measures cumulative gas cost of filling multiple orders, each with 2-hop payout
    ///      This amplifies the hop conversion cost across multiple fills
    function test_gas_2hop_five_orders_fill() public {
        PoolKey memory contentKey = contentCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(contentKey.currency0) == address(contentCoin);
        address orderCoin = LimitOrderCommon.getOrderCoin(contentKey, isCurrency0);

        // Create 5 orders at different price levels
        uint256 orderSize = 25e18;
        (uint256[] memory orderSizes, int24[] memory orderTicks) = _buildDeterministicOrders(contentKey, isCurrency0, 5, orderSize);

        uint256 totalSize = 0;
        for (uint256 i = 0; i < orderSizes.length; i++) {
            totalSize += orderSizes[i];
        }

        // Fund maker
        if (orderCoin == address(0)) {
            vm.deal(users.seller, totalSize);
        } else {
            deal(orderCoin, users.seller, totalSize);
            vm.prank(users.seller);
            IERC20(orderCoin).approve(address(limitOrderBook), totalSize);
        }

        // Create orders
        vm.recordLogs();
        vm.prank(users.seller);
        limitOrderBook.create{value: orderCoin == address(0) ? totalSize : 0}(contentKey, isCurrency0, orderSizes, orderTicks, users.seller);
        CreatedOrderLog[] memory created = _decodeCreatedLogs(vm.getRecordedLogs());
        require(created.length == 5, "Expected 5 orders");

        // Move price to make all orders fillable
        _movePriceBeyondTicksWithAutoFillDisabled(created);

        // Fill all 5 orders - each triggers multi-hop payout with hook recursion
        (int24 startTick, int24 endTick) = _tickWindow(created, contentKey);
        gasStart = gasleft();
        limitOrderBook.fill(contentKey, isCurrency0, startTick, endTick, 5, address(0));
        gasUsed = gasStart - gasleft();

        emit log_named_uint("FIVE_ORDERS_MULTIHOP_PAYOUT_GAS", gasUsed);
    }

    /// @notice Test 5: Empty fill (no orders to fill) to measure baseline traversal cost
    /// @dev Measures overhead of fill() when no orders exist in the range
    function test_gas_empty_fill() public {
        PoolKey memory key = creatorCoin.getPoolKey();

        gasStart = gasleft();
        limitOrderBook.fill(key, true, -type(int24).max, type(int24).max, 5, address(0));
        gasUsed = gasStart - gasleft();

        emit log_named_uint("EMPTY_FILL_GAS", gasUsed);
    }

    // ============ Tier 1 Extended Benchmarks ============

    /// @notice Test 6: Ten orders 2-hop fill - validates linear scaling
    /// @dev Proves gas scales linearly beyond 5 orders (content → creator → ZORA path)
    function test_gas_2hop_ten_orders_fill() public {
        PoolKey memory contentKey = contentCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(contentKey.currency0) == address(contentCoin);
        address orderCoin = LimitOrderCommon.getOrderCoin(contentKey, isCurrency0);

        // Create 10 orders at different price levels
        uint256 orderSize = 25e18;
        (uint256[] memory orderSizes, int24[] memory orderTicks) = _buildDeterministicOrders(contentKey, isCurrency0, 10, orderSize);

        uint256 totalSize = 0;
        for (uint256 i = 0; i < orderSizes.length; i++) {
            totalSize += orderSizes[i];
        }

        // Fund maker
        if (orderCoin == address(0)) {
            vm.deal(users.seller, totalSize);
        } else {
            deal(orderCoin, users.seller, totalSize);
            vm.prank(users.seller);
            IERC20(orderCoin).approve(address(limitOrderBook), totalSize);
        }

        // Create orders
        vm.recordLogs();
        vm.prank(users.seller);
        limitOrderBook.create{value: orderCoin == address(0) ? totalSize : 0}(contentKey, isCurrency0, orderSizes, orderTicks, users.seller);
        CreatedOrderLog[] memory created = _decodeCreatedLogs(vm.getRecordedLogs());
        require(created.length == 10, "Expected 10 orders");

        // Move price to make all orders fillable
        _movePriceBeyondTicksWithAutoFillDisabled(created);

        // Fill all 10 orders - measures scaling behavior
        (int24 startTick, int24 endTick) = _tickWindow(created, contentKey);
        gasStart = gasleft();
        limitOrderBook.fill(contentKey, isCurrency0, startTick, endTick, 10, address(0));
        gasUsed = gasStart - gasleft();

        emit log_named_uint("TEN_ORDERS_MULTIHOP_PAYOUT_GAS", gasUsed);
    }

    /// @notice Test 7: User swap with auto-fill (2-hop) - CRITICAL user-facing metric
    /// @dev Measures gas when users swap and orders automatically fill (content → creator → ZORA)
    function test_gas_2hop_user_swap_triggers_autofill() public {
        PoolKey memory contentKey = contentCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(contentKey.currency0) == address(contentCoin);
        address orderCoin = LimitOrderCommon.getOrderCoin(contentKey, isCurrency0);

        // Create 5 fillable orders at different ticks
        uint256 orderSize = 25e18;
        (uint256[] memory orderSizes, int24[] memory orderTicks) = _buildDeterministicOrders(contentKey, isCurrency0, 5, orderSize);

        uint256 totalSize = 0;
        for (uint256 i = 0; i < orderSizes.length; i++) {
            totalSize += orderSizes[i];
        }

        // Fund maker
        if (orderCoin == address(0)) {
            vm.deal(users.seller, totalSize);
        } else {
            deal(orderCoin, users.seller, totalSize);
            vm.prank(users.seller);
            IERC20(orderCoin).approve(address(limitOrderBook), totalSize);
        }

        // Create orders (but don't move price yet)
        vm.prank(users.seller);
        limitOrderBook.create{value: orderCoin == address(0) ? totalSize : 0}(contentKey, isCurrency0, orderSizes, orderTicks, users.seller);

        // User swaps THROUGH the order ticks, triggering auto-fill
        // This is what users actually experience!
        uint256 swapAmount = 200e18; // Large enough to cross all 5 orders

        gasStart = gasleft();
        _executeMultiHopSwap(users.buyer, swapAmount, _buildSwapRoute(contentKey), _buildSwapHookData(2));
        gasUsed = gasStart - gasleft();

        emit log_named_uint("USER_SWAP_WITH_AUTOFILL_GAS", gasUsed);
    }

    /// @notice Test 8: Fee conversion self-recursion - isolates BIGGEST savings
    /// @dev Measures impact of sender == address(this) check (affects EVERY swap)
    function test_gas_large_swap_with_fee_conversion() public {
        PoolKey memory key = creatorCoin.getPoolKey();

        // Execute a large swap that generates significant fees
        // The hook will collect fees and convert them to backing currency
        // With optimization: fee conversion swap is skipped (sender == address(this))
        // This optimization benefits EVERY swap, not just limit order fills!
        uint256 largeSwapAmount = 500e18;

        gasStart = gasleft();
        _executeSingleHopSwap(users.buyer, largeSwapAmount, key, bytes(""));
        gasUsed = gasStart - gasleft();

        emit log_named_uint("LARGE_SWAP_WITH_FEE_CONVERSION_GAS", gasUsed);
    }

    // ============ Tier 2 Extended Benchmarks ============

    /// @notice Test 9: Max fill count stress test - validates system handles configured limit
    /// @dev Tests 25 orders (current maxFillCount setting) to ensure system stays under block gas limit
    function test_gas_max_fillcount_stress_test() public {
        PoolKey memory contentKey = contentCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(contentKey.currency0) == address(contentCoin);
        address orderCoin = LimitOrderCommon.getOrderCoin(contentKey, isCurrency0);

        // Create 25 orders at different price levels (current maxFillCount)
        uint256 orderSize = 25e18;
        (uint256[] memory orderSizes, int24[] memory orderTicks) = _buildDeterministicOrders(contentKey, isCurrency0, 25, orderSize);

        uint256 totalSize = 0;
        for (uint256 i = 0; i < orderSizes.length; i++) {
            totalSize += orderSizes[i];
        }

        // Fund maker
        if (orderCoin == address(0)) {
            vm.deal(users.seller, totalSize);
        } else {
            deal(orderCoin, users.seller, totalSize);
            vm.prank(users.seller);
            IERC20(orderCoin).approve(address(limitOrderBook), totalSize);
        }

        // Create orders
        vm.recordLogs();
        vm.prank(users.seller);
        limitOrderBook.create{value: orderCoin == address(0) ? totalSize : 0}(contentKey, isCurrency0, orderSizes, orderTicks, users.seller);
        CreatedOrderLog[] memory created = _decodeCreatedLogs(vm.getRecordedLogs());
        require(created.length == 25, "Expected 25 orders");

        // Move price to make all orders fillable
        _movePriceBeyondTicksWithAutoFillDisabled(created);

        // Fill all 25 orders - stress test at max configured limit
        (int24 startTick, int24 endTick) = _tickWindow(created, contentKey);
        gasStart = gasleft();
        limitOrderBook.fill(contentKey, isCurrency0, startTick, endTick, 25, address(0));
        gasUsed = gasStart - gasleft();

        emit log_named_uint("MAX_FILLCOUNT_25_ORDERS_GAS", gasUsed);
    }

    /// @notice Test 10: Mixed order sizes - tests realistic workload with varying liquidity
    /// @dev Creates 5 orders with different sizes to test if gas is proportional to liquidity
    function test_gas_mixed_order_sizes() public {
        PoolKey memory contentKey = contentCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(contentKey.currency0) == address(contentCoin);
        address orderCoin = LimitOrderCommon.getOrderCoin(contentKey, isCurrency0);

        // Create 5 orders with varying sizes: 1, 10, 50, 100, 250 ETH
        uint256[] memory customSizes = new uint256[](5);
        customSizes[0] = 1e18;
        customSizes[1] = 10e18;
        customSizes[2] = 50e18;
        customSizes[3] = 100e18;
        customSizes[4] = 250e18;

        (uint256[] memory orderSizes, int24[] memory orderTicks) = _buildDeterministicOrders(contentKey, isCurrency0, 5, 0);

        // Override with custom sizes
        for (uint256 i = 0; i < customSizes.length; i++) {
            orderSizes[i] = customSizes[i];
        }

        uint256 totalSize = 0;
        for (uint256 i = 0; i < orderSizes.length; i++) {
            totalSize += orderSizes[i];
        }

        // Fund maker
        if (orderCoin == address(0)) {
            vm.deal(users.seller, totalSize);
        } else {
            deal(orderCoin, users.seller, totalSize);
            vm.prank(users.seller);
            IERC20(orderCoin).approve(address(limitOrderBook), totalSize);
        }

        // Create orders
        vm.recordLogs();
        vm.prank(users.seller);
        limitOrderBook.create{value: orderCoin == address(0) ? totalSize : 0}(contentKey, isCurrency0, orderSizes, orderTicks, users.seller);
        CreatedOrderLog[] memory created = _decodeCreatedLogs(vm.getRecordedLogs());
        require(created.length == 5, "Expected 5 orders");

        // Move price to make all orders fillable
        _movePriceBeyondTicksWithAutoFillDisabled(created);

        // Fill all orders - measures if gas scales with liquidity
        (int24 startTick, int24 endTick) = _tickWindow(created, contentKey);
        gasStart = gasleft();
        limitOrderBook.fill(contentKey, isCurrency0, startTick, endTick, 5, address(0));
        gasUsed = gasStart - gasleft();

        emit log_named_uint("MIXED_ORDER_SIZES_GAS", gasUsed);
    }

    /// @notice Test 11: Same-tick orders - tests dense liquidity with multiple orders at identical price
    /// @dev Creates 5 orders all at the same tick to test FIFO traversal efficiency
    function test_gas_same_tick_orders() public {
        PoolKey memory contentKey = contentCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(contentKey.currency0) == address(contentCoin);
        address orderCoin = LimitOrderCommon.getOrderCoin(contentKey, isCurrency0);

        // Use _buildDeterministicOrders to get ticks, then set them all to the same value
        uint256 orderSize = 25e18;
        (uint256[] memory orderSizes, int24[] memory orderTicks) = _buildDeterministicOrders(contentKey, isCurrency0, 5, orderSize);

        // Override all ticks to be the same (use the first tick as the common tick)
        int24 commonTick = orderTicks[0];
        for (uint256 i = 1; i < orderTicks.length; i++) {
            orderTicks[i] = commonTick;
        }

        uint256 totalSize = 0;
        for (uint256 i = 0; i < orderSizes.length; i++) {
            totalSize += orderSizes[i];
        }

        // Fund maker
        if (orderCoin == address(0)) {
            vm.deal(users.seller, totalSize);
        } else {
            deal(orderCoin, users.seller, totalSize);
            vm.prank(users.seller);
            IERC20(orderCoin).approve(address(limitOrderBook), totalSize);
        }

        // Create orders
        vm.recordLogs();
        vm.prank(users.seller);
        limitOrderBook.create{value: orderCoin == address(0) ? totalSize : 0}(contentKey, isCurrency0, orderSizes, orderTicks, users.seller);
        CreatedOrderLog[] memory created = _decodeCreatedLogs(vm.getRecordedLogs());
        require(created.length == 5, "Expected 5 orders");

        // Move price to make all orders fillable
        _movePriceBeyondTicksWithAutoFillDisabled(created);

        // Fill all orders - measures dense liquidity traversal cost
        (int24 startTick, int24 endTick) = _tickWindow(created, contentKey);
        gasStart = gasleft();
        limitOrderBook.fill(contentKey, isCurrency0, startTick, endTick, 5, address(0));
        gasUsed = gasStart - gasleft();

        emit log_named_uint("SAME_TICK_ORDERS_GAS", gasUsed);
    }

    // ============ Phase 1 Stress Tests: User Auto-Fill at Scale ============
    // Critical tests for determining optimal maxFillCount in production

    /// @notice Test 12: User swap auto-fill with 10 orders
    /// @dev Establishes baseline for linear scaling validation
    function test_gas_user_swap_autofill_10_orders() public {
        PoolKey memory contentKey = contentCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(contentKey.currency0) == address(contentCoin);
        address orderCoin = LimitOrderCommon.getOrderCoin(contentKey, isCurrency0);

        // Create 10 orders at different ticks
        uint256 orderSize = 25e18;
        (uint256[] memory orderSizes, int24[] memory orderTicks) = _buildDeterministicOrders(contentKey, isCurrency0, 10, orderSize);

        uint256 totalSize = 0;
        for (uint256 i = 0; i < orderSizes.length; i++) {
            totalSize += orderSizes[i];
        }

        // Fund maker
        if (orderCoin == address(0)) {
            vm.deal(users.seller, totalSize);
        } else {
            deal(orderCoin, users.seller, totalSize);
            vm.prank(users.seller);
            IERC20(orderCoin).approve(address(limitOrderBook), totalSize);
        }

        // Create orders (but don't move price yet)
        vm.prank(users.seller);
        limitOrderBook.create{value: orderCoin == address(0) ? totalSize : 0}(contentKey, isCurrency0, orderSizes, orderTicks, users.seller);

        // User swaps THROUGH all 10 order ticks, triggering auto-fill
        uint256 swapAmount = 500e18; // Large enough to cross all 10 orders

        gasStart = gasleft();
        _executeMultiHopSwap(users.buyer, swapAmount, _buildSwapRoute(contentKey), _buildSwapHookData(2));
        gasUsed = gasStart - gasleft();

        emit log_named_uint("USER_SWAP_AUTOFILL_10_ORDERS_GAS", gasUsed);
    }

    /// @notice Test 13: User swap auto-fill with 25 orders (current maxFillCount)
    /// @dev Tests current production configuration
    function test_gas_user_swap_autofill_25_orders() public {
        PoolKey memory contentKey = contentCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(contentKey.currency0) == address(contentCoin);
        address orderCoin = LimitOrderCommon.getOrderCoin(contentKey, isCurrency0);

        // Create 25 orders at different ticks
        uint256 orderSize = 25e18;
        (uint256[] memory orderSizes, int24[] memory orderTicks) = _buildDeterministicOrders(contentKey, isCurrency0, 25, orderSize);

        uint256 totalSize = 0;
        for (uint256 i = 0; i < orderSizes.length; i++) {
            totalSize += orderSizes[i];
        }

        // Fund maker
        if (orderCoin == address(0)) {
            vm.deal(users.seller, totalSize);
        } else {
            deal(orderCoin, users.seller, totalSize);
            vm.prank(users.seller);
            IERC20(orderCoin).approve(address(limitOrderBook), totalSize);
        }

        // Create orders (but don't move price yet)
        vm.prank(users.seller);
        limitOrderBook.create{value: orderCoin == address(0) ? totalSize : 0}(contentKey, isCurrency0, orderSizes, orderTicks, users.seller);

        // User swaps THROUGH all 25 order ticks, triggering auto-fill
        uint256 swapAmount = 1000e18; // Large enough to cross all 25 orders

        gasStart = gasleft();
        _executeMultiHopSwap(users.buyer, swapAmount, _buildSwapRoute(contentKey), _buildSwapHookData(2));
        gasUsed = gasStart - gasleft();

        emit log_named_uint("USER_SWAP_AUTOFILL_25_ORDERS_GAS", gasUsed);
    }

    /// @notice Test 14: User swap auto-fill with 40 orders (recommended candidate)
    /// @dev Tests recommended maxFillCount value (37% block utilization, 2.7× safety margin)
    function test_gas_user_swap_autofill_40_orders() public {
        PoolKey memory contentKey = contentCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(contentKey.currency0) == address(contentCoin);
        address orderCoin = LimitOrderCommon.getOrderCoin(contentKey, isCurrency0);

        // Create 40 orders at different ticks
        uint256 orderSize = 25e18;
        (uint256[] memory orderSizes, int24[] memory orderTicks) = _buildDeterministicOrders(contentKey, isCurrency0, 40, orderSize);

        uint256 totalSize = 0;
        for (uint256 i = 0; i < orderSizes.length; i++) {
            totalSize += orderSizes[i];
        }

        // Fund maker
        if (orderCoin == address(0)) {
            vm.deal(users.seller, totalSize);
        } else {
            deal(orderCoin, users.seller, totalSize);
            vm.prank(users.seller);
            IERC20(orderCoin).approve(address(limitOrderBook), totalSize);
        }

        // Create orders (but don't move price yet)
        vm.prank(users.seller);
        limitOrderBook.create{value: orderCoin == address(0) ? totalSize : 0}(contentKey, isCurrency0, orderSizes, orderTicks, users.seller);

        // User swaps THROUGH all 40 order ticks, triggering auto-fill
        uint256 swapAmount = 1500e18; // Large enough to cross all 40 orders

        gasStart = gasleft();
        _executeMultiHopSwap(users.buyer, swapAmount, _buildSwapRoute(contentKey), _buildSwapHookData(2));
        gasUsed = gasStart - gasleft();

        emit log_named_uint("USER_SWAP_AUTOFILL_40_ORDERS_GAS", gasUsed);
    }

    /// @notice Test 15: User swap auto-fill with 50 orders (aggressive candidate)
    /// @dev Tests aggressive maxFillCount value (43% block utilization, 2.3× safety margin)
    function test_gas_user_swap_autofill_50_orders() public {
        PoolKey memory contentKey = contentCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(contentKey.currency0) == address(contentCoin);
        address orderCoin = LimitOrderCommon.getOrderCoin(contentKey, isCurrency0);

        // Create 50 orders at different ticks
        uint256 orderSize = 25e18;
        (uint256[] memory orderSizes, int24[] memory orderTicks) = _buildDeterministicOrders(contentKey, isCurrency0, 50, orderSize);

        uint256 totalSize = 0;
        for (uint256 i = 0; i < orderSizes.length; i++) {
            totalSize += orderSizes[i];
        }

        // Fund maker
        if (orderCoin == address(0)) {
            vm.deal(users.seller, totalSize);
        } else {
            deal(orderCoin, users.seller, totalSize);
            vm.prank(users.seller);
            IERC20(orderCoin).approve(address(limitOrderBook), totalSize);
        }

        // Create orders (but don't move price yet)
        vm.prank(users.seller);
        limitOrderBook.create{value: orderCoin == address(0) ? totalSize : 0}(contentKey, isCurrency0, orderSizes, orderTicks, users.seller);

        // User swaps THROUGH all 50 order ticks, triggering auto-fill
        uint256 swapAmount = 2000e18; // Large enough to cross all 50 orders

        gasStart = gasleft();
        _executeMultiHopSwap(users.buyer, swapAmount, _buildSwapRoute(contentKey), _buildSwapHookData(2));
        gasUsed = gasStart - gasleft();

        emit log_named_uint("USER_SWAP_AUTOFILL_50_ORDERS_GAS", gasUsed);
    }

    // ============ Phase 2 Stress Tests: Extended Scaling Validation ============
    // Tests to validate safety margins beyond recommended maxFillCount

    /// @notice Test 16: User swap auto-fill with 75 orders (stress test)
    /// @dev Tests well beyond recommended maxFillCount to validate safety margins
    function test_gas_user_swap_autofill_75_orders() public {
        // Increase maxFillCount for this test
        vm.prank(users.factoryOwner);
        limitOrderBook.setMaxFillCount(100);

        PoolKey memory contentKey = contentCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(contentKey.currency0) == address(contentCoin);
        address orderCoin = LimitOrderCommon.getOrderCoin(contentKey, isCurrency0);

        // Create 75 orders at different ticks
        uint256 orderSize = 25e18;
        (uint256[] memory orderSizes, int24[] memory orderTicks) = _buildDeterministicOrders(contentKey, isCurrency0, 75, orderSize);

        uint256 totalSize = 0;
        for (uint256 i = 0; i < orderSizes.length; i++) {
            totalSize += orderSizes[i];
        }

        // Fund maker
        if (orderCoin == address(0)) {
            vm.deal(users.seller, totalSize);
        } else {
            deal(orderCoin, users.seller, totalSize);
            vm.prank(users.seller);
            IERC20(orderCoin).approve(address(limitOrderBook), totalSize);
        }

        // Create orders (but don't move price yet)
        vm.prank(users.seller);
        limitOrderBook.create{value: orderCoin == address(0) ? totalSize : 0}(contentKey, isCurrency0, orderSizes, orderTicks, users.seller);

        // User swaps THROUGH all 75 order ticks, triggering auto-fill
        uint256 swapAmount = 3000e18; // Large enough to cross all 75 orders

        gasStart = gasleft();
        _executeMultiHopSwap(users.buyer, swapAmount, _buildSwapRoute(contentKey), _buildSwapHookData(2));
        gasUsed = gasStart - gasleft();

        emit log_named_uint("USER_SWAP_AUTOFILL_75_ORDERS_GAS", gasUsed);
    }

    /// @notice Test 17: User swap auto-fill with 100 orders (max stress test)
    /// @dev Tests maximum scaling to identify absolute upper limits
    function test_gas_user_swap_autofill_100_orders() public {
        // Increase maxFillCount for this test
        vm.prank(users.factoryOwner);
        limitOrderBook.setMaxFillCount(100);

        PoolKey memory contentKey = contentCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(contentKey.currency0) == address(contentCoin);
        address orderCoin = LimitOrderCommon.getOrderCoin(contentKey, isCurrency0);

        // Create 100 orders at different ticks
        uint256 orderSize = 25e18;
        (uint256[] memory orderSizes, int24[] memory orderTicks) = _buildDeterministicOrders(contentKey, isCurrency0, 100, orderSize);

        uint256 totalSize = 0;
        for (uint256 i = 0; i < orderSizes.length; i++) {
            totalSize += orderSizes[i];
        }

        // Fund maker
        if (orderCoin == address(0)) {
            vm.deal(users.seller, totalSize);
        } else {
            deal(orderCoin, users.seller, totalSize);
            vm.prank(users.seller);
            IERC20(orderCoin).approve(address(limitOrderBook), totalSize);
        }

        // Create orders (but don't move price yet)
        vm.prank(users.seller);
        limitOrderBook.create{value: orderCoin == address(0) ? totalSize : 0}(contentKey, isCurrency0, orderSizes, orderTicks, users.seller);

        // User swaps THROUGH all 100 order ticks, triggering auto-fill
        uint256 swapAmount = 4000e18; // Large enough to cross all 100 orders

        gasStart = gasleft();
        _executeMultiHopSwap(users.buyer, swapAmount, _buildSwapRoute(contentKey), _buildSwapHookData(2));
        gasUsed = gasStart - gasleft();

        emit log_named_uint("USER_SWAP_AUTOFILL_100_ORDERS_GAS", gasUsed);
    }

    /// @notice Test 18: Backend manual fill with 50 orders
    /// @dev Tests backend/bot operations - isolated fill() call without user swap overhead
    function test_gas_backend_manual_fill_50_orders() public {
        // Increase maxFillCount for this test
        vm.prank(users.factoryOwner);
        limitOrderBook.setMaxFillCount(100);

        PoolKey memory contentKey = contentCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(contentKey.currency0) == address(contentCoin);
        address orderCoin = LimitOrderCommon.getOrderCoin(contentKey, isCurrency0);

        // Create 50 orders at different ticks
        uint256 orderSize = 25e18;
        (uint256[] memory orderSizes, int24[] memory orderTicks) = _buildDeterministicOrders(contentKey, isCurrency0, 50, orderSize);

        uint256 totalSize = 0;
        for (uint256 i = 0; i < orderSizes.length; i++) {
            totalSize += orderSizes[i];
        }

        // Fund maker
        if (orderCoin == address(0)) {
            vm.deal(users.seller, totalSize);
        } else {
            deal(orderCoin, users.seller, totalSize);
            vm.prank(users.seller);
            IERC20(orderCoin).approve(address(limitOrderBook), totalSize);
        }

        // Create orders
        vm.recordLogs();
        vm.prank(users.seller);
        limitOrderBook.create{value: orderCoin == address(0) ? totalSize : 0}(contentKey, isCurrency0, orderSizes, orderTicks, users.seller);
        CreatedOrderLog[] memory created = _decodeCreatedLogs(vm.getRecordedLogs());
        require(created.length == 50, "Expected 50 orders");

        // Move price to make all orders fillable
        _movePriceBeyondTicksWithAutoFillDisabled(created);

        // Backend fills orders - measures isolated fill operation
        (int24 startTick, int24 endTick) = _tickWindow(created, contentKey);
        gasStart = gasleft();
        limitOrderBook.fill(contentKey, isCurrency0, startTick, endTick, 50, address(0));
        gasUsed = gasStart - gasleft();

        emit log_named_uint("BACKEND_MANUAL_FILL_50_ORDERS_GAS", gasUsed);
    }

    /// @notice Test 19: Backend manual fill with 100 orders
    /// @dev Tests large backend batch operations
    function test_gas_backend_manual_fill_100_orders() public {
        // Increase maxFillCount for this test
        vm.prank(users.factoryOwner);
        limitOrderBook.setMaxFillCount(100);

        PoolKey memory contentKey = contentCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(contentKey.currency0) == address(contentCoin);
        address orderCoin = LimitOrderCommon.getOrderCoin(contentKey, isCurrency0);

        // Create 100 orders at different ticks
        uint256 orderSize = 25e18;
        (uint256[] memory orderSizes, int24[] memory orderTicks) = _buildDeterministicOrders(contentKey, isCurrency0, 100, orderSize);

        uint256 totalSize = 0;
        for (uint256 i = 0; i < orderSizes.length; i++) {
            totalSize += orderSizes[i];
        }

        // Fund maker
        if (orderCoin == address(0)) {
            vm.deal(users.seller, totalSize);
        } else {
            deal(orderCoin, users.seller, totalSize);
            vm.prank(users.seller);
            IERC20(orderCoin).approve(address(limitOrderBook), totalSize);
        }

        // Create orders
        vm.recordLogs();
        vm.prank(users.seller);
        limitOrderBook.create{value: orderCoin == address(0) ? totalSize : 0}(contentKey, isCurrency0, orderSizes, orderTicks, users.seller);
        CreatedOrderLog[] memory created = _decodeCreatedLogs(vm.getRecordedLogs());
        require(created.length == 100, "Expected 100 orders");

        // Move price to make all orders fillable
        _movePriceBeyondTicksWithAutoFillDisabled(created);

        // Backend fills orders - measures isolated fill operation
        (int24 startTick, int24 endTick) = _tickWindow(created, contentKey);
        gasStart = gasleft();
        limitOrderBook.fill(contentKey, isCurrency0, startTick, endTick, 100, address(0));
        gasUsed = gasStart - gasleft();

        emit log_named_uint("BACKEND_MANUAL_FILL_100_ORDERS_GAS", gasUsed);
    }

    /// @notice Test 20: Backend manual fill with 150 orders (pathological case)
    /// @dev Tests extreme backend batch - likely exceeds reasonable block gas limits
    function test_gas_backend_manual_fill_150_orders() public {
        // Increase maxFillCount for this test
        vm.prank(users.factoryOwner);
        limitOrderBook.setMaxFillCount(200);

        PoolKey memory contentKey = contentCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(contentKey.currency0) == address(contentCoin);
        address orderCoin = LimitOrderCommon.getOrderCoin(contentKey, isCurrency0);

        // Create 150 orders at different ticks
        uint256 orderSize = 25e18;
        (uint256[] memory orderSizes, int24[] memory orderTicks) = _buildDeterministicOrders(contentKey, isCurrency0, 150, orderSize);

        uint256 totalSize = 0;
        for (uint256 i = 0; i < orderSizes.length; i++) {
            totalSize += orderSizes[i];
        }

        // Fund maker
        if (orderCoin == address(0)) {
            vm.deal(users.seller, totalSize);
        } else {
            deal(orderCoin, users.seller, totalSize);
            vm.prank(users.seller);
            IERC20(orderCoin).approve(address(limitOrderBook), totalSize);
        }

        // Create orders
        vm.recordLogs();
        vm.prank(users.seller);
        limitOrderBook.create{value: orderCoin == address(0) ? totalSize : 0}(contentKey, isCurrency0, orderSizes, orderTicks, users.seller);
        CreatedOrderLog[] memory created = _decodeCreatedLogs(vm.getRecordedLogs());
        require(created.length == 150, "Expected 150 orders");

        // Move price to make all orders fillable
        _movePriceBeyondTicksWithAutoFillDisabled(created);

        // Backend fills orders - measures extreme batch operation
        (int24 startTick, int24 endTick) = _tickWindow(created, contentKey);
        gasStart = gasleft();
        limitOrderBook.fill(contentKey, isCurrency0, startTick, endTick, 150, address(0));
        gasUsed = gasStart - gasleft();

        emit log_named_uint("BACKEND_MANUAL_FILL_150_ORDERS_GAS", gasUsed);
    }

    // ============ Helper Functions ============

    /// @dev Helper to build swap route for multi-hop swaps
    function _buildSwapRoute(PoolKey memory contentKey) internal view returns (PoolKey[] memory) {
        PoolKey[] memory route = new PoolKey[](2);
        route[0] = creatorCoin.getPoolKey();
        route[1] = contentKey;
        return route;
    }

    /// @dev Helper to build hook data for multi-hop swaps
    function _buildSwapHookData(uint256 hops) internal pure returns (bytes[] memory) {
        bytes[] memory hookData = new bytes[](hops);
        for (uint256 i = 0; i < hops; i++) {
            hookData[i] = bytes("");
        }
        return hookData;
    }

    /// @notice Helper to move price beyond order ticks without triggering automatic fills
    /// @dev Disables hook's auto-fill, executes swap, re-enables auto-fill
    function _movePriceBeyondTicksWithAutoFillDisabled(CreatedOrderLog[] memory created) internal override {
        uint256 previousMaxFillCount = limitOrderBook.getMaxFillCount();
        vm.prank(users.factoryOwner);
        limitOrderBook.setMaxFillCount(0);

        _movePriceBeyondTicks(created);

        vm.prank(users.factoryOwner);
        limitOrderBook.setMaxFillCount(previousMaxFillCount);
    }

    /// @notice Helper to actually move the price by executing a large swap
    function _movePriceBeyondTicks(CreatedOrderLog[] memory created) internal override {
        if (created.length == 0) return;

        PoolKey memory key = creatorCoin.getPoolKey();
        uint256 swapAmount = 1000e18;

        // Content coin pools sit behind creator coin pools, so we need to route ZORA -> Creator -> Content
        if (created[0].coin == address(contentCoin)) {
            PoolKey[] memory route = new PoolKey[](2);
            route[0] = creatorCoin.getPoolKey();
            route[1] = contentCoin.getPoolKey();

            bytes[] memory hookData = new bytes[](2);
            hookData[0] = bytes("");
            hookData[1] = bytes("");

            _executeMultiHopSwap(users.buyer, swapAmount, route, hookData);
            return;
        }

        // Execute a large swap to move price across all order ticks
        _executeSingleHopSwap(users.buyer, swapAmount, key, bytes(""));
    }

    // ============ Hop Coverage Tests ============

    /// @notice Test H1: 1-hop single order fill (creator coin → ZORA)
    /// @dev Most common production path - creator coin limit orders payout in ZORA
    function test_gas_1hop_single_order_fill() public {
        PoolKey memory key = creatorCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(key.currency0) == address(creatorCoin);
        address orderCoin = LimitOrderCommon.getOrderCoin(key, isCurrency0);

        // Create 1 order on creatorCoin pool
        uint256 orderSize = 25e18;
        (uint256[] memory orderSizes, int24[] memory orderTicks) = _buildDeterministicOrders(key, isCurrency0, 1, orderSize);

        // Fund maker
        if (orderCoin == address(0)) {
            vm.deal(users.seller, orderSize);
        } else {
            deal(orderCoin, users.seller, orderSize);
            vm.prank(users.seller);
            IERC20(orderCoin).approve(address(limitOrderBook), orderSize);
        }

        // Create order
        vm.recordLogs();
        vm.prank(users.seller);
        limitOrderBook.create{value: orderCoin == address(0) ? orderSize : 0}(key, isCurrency0, orderSizes, orderTicks, users.seller);
        CreatedOrderLog[] memory created = _decodeCreatedLogs(vm.getRecordedLogs());
        require(created.length == 1, "Expected 1 order");

        // Move price to make order fillable
        _movePriceBeyondTicksWithAutoFillDisabled(created);

        // Fill order - measures 1-hop payout (creator coin → ZORA)
        (int24 startTick, int24 endTick) = _tickWindow(created, key);
        gasStart = gasleft();
        limitOrderBook.fill(key, isCurrency0, startTick, endTick, 1, address(0));
        gasUsed = gasStart - gasleft();

        emit log_named_uint("SINGLE_ORDER_1HOP_GAS", gasUsed);
    }

    /// @notice Test H2: 1-hop user auto-fill with 40 orders
    /// @dev Production-scale measurement for most common creator coin scenario
    function test_gas_1hop_user_swap_autofill_40_orders() public {
        PoolKey memory key = creatorCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(key.currency0) == address(creatorCoin);
        address orderCoin = LimitOrderCommon.getOrderCoin(key, isCurrency0);

        // Create 40 orders at different ticks
        uint256 orderSize = 25e18;
        (uint256[] memory orderSizes, int24[] memory orderTicks) = _buildDeterministicOrders(key, isCurrency0, 40, orderSize);

        uint256 totalSize = 0;
        for (uint256 i = 0; i < orderSizes.length; i++) {
            totalSize += orderSizes[i];
        }

        // Fund maker
        if (orderCoin == address(0)) {
            vm.deal(users.seller, totalSize);
        } else {
            deal(orderCoin, users.seller, totalSize);
            vm.prank(users.seller);
            IERC20(orderCoin).approve(address(limitOrderBook), totalSize);
        }

        // Create orders (but don't move price yet)
        vm.prank(users.seller);
        limitOrderBook.create{value: orderCoin == address(0) ? totalSize : 0}(key, isCurrency0, orderSizes, orderTicks, users.seller);

        // User swaps THROUGH all 40 orders with 1-hop payout (creator → ZORA)
        uint256 swapAmount = 1500e18; // Large enough to cross all 40 orders

        gasStart = gasleft();
        _executeSingleHopSwap(users.buyer, swapAmount, key, bytes(""));
        gasUsed = gasStart - gasleft();

        emit log_named_uint("USER_SWAP_AUTOFILL_1HOP_40_ORDERS_GAS", gasUsed);
    }

    /// @notice Test H3: 1-hop user auto-fill with 50 orders (PRODUCTION DEFAULT)
    /// @dev Validates recommended maxFillCount=50 for most common creator coin scenario
    function test_gas_1hop_user_swap_autofill_50_orders() public {
        PoolKey memory key = creatorCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(key.currency0) == address(creatorCoin);
        address orderCoin = LimitOrderCommon.getOrderCoin(key, isCurrency0);

        // Create 50 orders at different ticks
        uint256 orderSize = 25e18;
        (uint256[] memory orderSizes, int24[] memory orderTicks) = _buildDeterministicOrders(key, isCurrency0, 50, orderSize);

        uint256 totalSize = 0;
        for (uint256 i = 0; i < orderSizes.length; i++) {
            totalSize += orderSizes[i];
        }

        // Fund maker
        if (orderCoin == address(0)) {
            vm.deal(users.seller, totalSize);
        } else {
            deal(orderCoin, users.seller, totalSize);
            vm.prank(users.seller);
            IERC20(orderCoin).approve(address(limitOrderBook), totalSize);
        }

        // Create orders (but don't move price yet)
        vm.prank(users.seller);
        limitOrderBook.create{value: orderCoin == address(0) ? totalSize : 0}(key, isCurrency0, orderSizes, orderTicks, users.seller);

        // User swaps THROUGH all 50 orders with 1-hop payout (creator → ZORA)
        uint256 swapAmount = 1875e18; // Large enough to cross all 50 orders

        gasStart = gasleft();
        _executeSingleHopSwap(users.buyer, swapAmount, key, bytes(""));
        gasUsed = gasStart - gasleft();

        emit log_named_uint("USER_SWAP_AUTOFILL_1HOP_50_ORDERS_GAS", gasUsed);
    }
}
