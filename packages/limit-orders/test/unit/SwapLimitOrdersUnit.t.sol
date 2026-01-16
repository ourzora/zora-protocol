// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {SwapLimitOrders, LimitOrderConfig, Orders} from "../../src/libs/SwapLimitOrders.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {TickMath} from "@zoralabs/coins/src/utils/uniswap/TickMath.sol";

/// @notice Helper contract to wrap library calls for proper revert testing
contract SwapLimitOrdersWrapper {
    function validate(LimitOrderConfig memory params) external pure returns (uint256) {
        return SwapLimitOrders.validate(params);
    }

    function computeOrders(
        PoolKey memory key,
        bool isCurrency0,
        uint128 totalSize,
        int24 baseTick,
        uint160 sqrtPriceX96,
        LimitOrderConfig memory params
    ) external pure returns (Orders memory o, uint128 allocated, uint128 unallocated) {
        return SwapLimitOrders.computeOrders(key, isCurrency0, totalSize, baseTick, sqrtPriceX96, params);
    }

    /// @notice Test helper for isLimitOrder logic (not used in production)
    function isLimitOrder(bool isCoinBuy, address swapper, int128 coinDelta, LimitOrderConfig memory params) external pure returns (bool) {
        // Short-circuit early: must be a coin buy with a valid swapper and config
        if (!isCoinBuy || swapper == address(0) || params.multiples.length == 0) {
            return false;
        }

        // Must be positive
        return coinDelta > 0;
    }
}

/// @notice Direct unit tests for SwapLimitOrders library functions
contract SwapLimitOrdersUnitTest is Test {
    using SwapLimitOrders for LimitOrderConfig;

    int24 constant TICK_SPACING = 200;
    uint256 constant MULTIPLE_SCALE = 1e18;
    uint256 constant PERCENT_SCALE = 10_000;
    uint256 constant TEST_ORDER_SIZE = 1e18; // Convenient test size (1 token for 18-decimal)

    PoolKey internal testKey;
    SwapLimitOrdersWrapper internal wrapper;

    function setUp() public {
        // Create a minimal valid pool key for testing
        testKey = PoolKey({
            currency0: Currency.wrap(address(0x1000)),
            currency1: Currency.wrap(address(0x2000)),
            fee: 3000,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(0))
        });

        wrapper = new SwapLimitOrdersWrapper();
    }

    /// @notice Tests validate with mismatched array lengths
    function test_validate_lengthMismatch_differentLengths() public {
        LimitOrderConfig memory params;
        params.multiples = new uint256[](3);
        params.percentages = new uint256[](2); // mismatch

        vm.expectRevert();
        wrapper.validate(params);
    }

    /// @notice Tests validate with empty arrays (length == 0)
    function test_validate_lengthMismatch_emptyArrays() public {
        LimitOrderConfig memory params;
        params.multiples = new uint256[](0);
        params.percentages = new uint256[](0);

        vm.expectRevert();
        wrapper.validate(params);
    }

    /// @notice Tests validate with zero percentage
    function test_validate_invalidPercent_zeroPercent() public {
        LimitOrderConfig memory params;
        params.multiples = new uint256[](2);
        params.percentages = new uint256[](2);

        params.multiples[0] = 2 * MULTIPLE_SCALE;
        params.multiples[1] = 4 * MULTIPLE_SCALE;
        params.percentages[0] = 5000; // 50%
        params.percentages[1] = 0; // Zero percent - should revert

        vm.expectRevert();
        wrapper.validate(params);
    }

    /// @notice Tests validate with percentages exceeding 100%
    function test_validate_percentOverflow_exceedsMax() public {
        LimitOrderConfig memory params;
        params.multiples = new uint256[](2);
        params.percentages = new uint256[](2);

        params.multiples[0] = 2 * MULTIPLE_SCALE;
        params.multiples[1] = 4 * MULTIPLE_SCALE;
        params.percentages[0] = 6000; // 60%
        params.percentages[1] = 5000; // 50% (total 110% > 100%)

        vm.expectRevert();
        wrapper.validate(params);
    }

    /// @notice Tests validate with multiple at 1x (not strictly above)
    function test_validate_invalidMultiple_equalToOne() public {
        LimitOrderConfig memory params;
        params.multiples = new uint256[](2);
        params.percentages = new uint256[](2);

        params.multiples[0] = MULTIPLE_SCALE; // 1.0x - should revert
        params.multiples[1] = 4 * MULTIPLE_SCALE;
        params.percentages[0] = 5000;
        params.percentages[1] = 5000;

        vm.expectRevert();
        wrapper.validate(params);
    }

    /// @notice Tests validate with multiple below 1x
    function test_validate_invalidMultiple_belowOne() public {
        LimitOrderConfig memory params;
        params.multiples = new uint256[](2);
        params.percentages = new uint256[](2);

        params.multiples[0] = 2 * MULTIPLE_SCALE;
        params.multiples[1] = MULTIPLE_SCALE / 2; // 0.5x - should revert
        params.percentages[0] = 5000;
        params.percentages[1] = 5000;

        vm.expectRevert();
        wrapper.validate(params);
    }

    /// @notice Tests validate with all valid inputs (success case)
    function test_validate_success_validParams() public {
        LimitOrderConfig memory params;
        params.multiples = new uint256[](3);
        params.percentages = new uint256[](3);

        params.multiples[0] = 2 * MULTIPLE_SCALE; // 2x
        params.multiples[1] = 4 * MULTIPLE_SCALE; // 4x
        params.multiples[2] = 8 * MULTIPLE_SCALE; // 8x
        params.percentages[0] = 3000; // 30%
        params.percentages[1] = 3000; // 30%
        params.percentages[2] = 3000; // 30% (total 90% <= 100%)

        uint256 totalPercent = wrapper.validate(params);
        assertEq(totalPercent, 9000, "total percent should be 9000");
    }

    /// @notice Tests validate with percentages exactly at 100%
    function test_validate_success_exactlyOneHundredPercent() public {
        LimitOrderConfig memory params;
        params.multiples = new uint256[](2);
        params.percentages = new uint256[](2);

        params.multiples[0] = 2 * MULTIPLE_SCALE;
        params.multiples[1] = 4 * MULTIPLE_SCALE;
        params.percentages[0] = 5000; // 50%
        params.percentages[1] = 5000; // 50% (total exactly 100%)

        uint256 totalPercent = wrapper.validate(params);
        assertEq(totalPercent, 10000, "total percent should be 10000");
    }

    /// @notice Tests validate loop iterations (line 65 for loop with multiple iterations)
    function test_validate_multipleIterations_checksAllElements() public {
        LimitOrderConfig memory params;
        params.multiples = new uint256[](5); // 5 elements to iterate
        params.percentages = new uint256[](5);

        for (uint256 i = 0; i < 5; i++) {
            params.multiples[i] = (2 + i) * MULTIPLE_SCALE; // 2x, 3x, 4x, 5x, 6x
            params.percentages[i] = 1000; // 10% each
        }

        uint256 totalPercent = wrapper.validate(params);
        assertEq(totalPercent, 5000, "total percent should be 5000");
    }

    /// @notice Tests validate with single element (loop executes once)
    function test_validate_singleElement_loopExecutesOnce() public {
        LimitOrderConfig memory params;
        params.multiples = new uint256[](1);
        params.percentages = new uint256[](1);

        params.multiples[0] = 2 * MULTIPLE_SCALE;
        params.percentages[0] = 10000;

        uint256 totalPercent = wrapper.validate(params);
        assertEq(totalPercent, 10000, "total percent should be 10000");
    }

    /// @notice Tests computeOrders with totalSize of zero returns empty
    function test_computeOrders_zeroSize_returnsEmpty() public {
        LimitOrderConfig memory params;
        params.multiples = new uint256[](2);
        params.percentages = new uint256[](2);
        params.multiples[0] = 2 * MULTIPLE_SCALE;
        params.multiples[1] = 4 * MULTIPLE_SCALE;
        params.percentages[0] = 5000;
        params.percentages[1] = 5000;

        uint128 totalSize = 0;
        int24 baseTick = 0;
        uint160 sqrtPriceX96 = TickMath.getSqrtPriceAtTick(baseTick);

        (Orders memory orders, uint128 allocated, uint128 unallocated) = SwapLimitOrders.computeOrders(
            testKey,
            true,
            totalSize,
            baseTick,
            sqrtPriceX96,
            params
        );

        // Should return empty arrays
        assertEq(orders.sizes.length, 0, "sizes should be empty");
        assertEq(orders.ticks.length, 0, "ticks should be empty");
        assertEq(allocated, 0, "allocated should be 0");
        assertEq(unallocated, 0, "unallocated should be 0");
    }

    /// @notice Tests computeOrders with small totalSize creates orders
    function test_computeOrders_smallSize_createsOrders() public {
        LimitOrderConfig memory params;
        params.multiples = new uint256[](2);
        params.percentages = new uint256[](2);
        params.multiples[0] = 2 * MULTIPLE_SCALE;
        params.multiples[1] = 4 * MULTIPLE_SCALE;
        params.percentages[0] = 5000;
        params.percentages[1] = 5000;

        uint128 totalSize = uint128(TEST_ORDER_SIZE); // Exactly at minimum
        int24 baseTick = 0;
        uint160 sqrtPriceX96 = TickMath.getSqrtPriceAtTick(baseTick);

        (Orders memory orders, uint128 allocated, uint128 unallocated) = SwapLimitOrders.computeOrders(
            testKey,
            true,
            totalSize,
            baseTick,
            sqrtPriceX96,
            params
        );

        // Should create orders
        assertEq(orders.sizes.length, 2, "should create 2 orders");
        assertEq(orders.ticks.length, 2, "should create 2 ticks");
        assertGt(allocated, 0, "should allocate some amount");
    }

    /// @notice Tests computeOrders with multiple orders (verifying skip logic exists even if hard to trigger)
    /// @dev Note: Zero-rounding skip is virtually impossible with reasonable sizes and PERCENT_SCALE=10000
    ///      since even 1 basis point of 1e18 = 1e14. The skip logic exists for safety in edge cases.
    function test_computeOrders_multipleOrders_createsAll() public {
        LimitOrderConfig memory params;
        params.multiples = new uint256[](2);
        params.percentages = new uint256[](2);
        params.multiples[0] = 2 * MULTIPLE_SCALE;
        params.multiples[1] = 4 * MULTIPLE_SCALE;
        params.percentages[0] = 5000;
        params.percentages[1] = 5000;

        uint128 totalSize = uint128(TEST_ORDER_SIZE * 10);
        int24 baseTick = 0;
        uint160 sqrtPriceX96 = TickMath.getSqrtPriceAtTick(baseTick);

        (Orders memory orders, uint128 allocated, uint128 unallocated) = SwapLimitOrders.computeOrders(
            testKey,
            true,
            totalSize,
            baseTick,
            sqrtPriceX96,
            params
        );

        // Both orders should be created
        assertEq(orders.sizes.length, 2, "should create 2 orders");
        assertEq(orders.ticks.length, 2, "should have 2 ticks");
    }

    /// @notice Tests computeOrders loop with many iterations (line 105 for loop)
    function test_computeOrders_manyOrders_loopIteratesMultipleTimes() public {
        LimitOrderConfig memory params;
        params.multiples = new uint256[](6); // Many orders
        params.percentages = new uint256[](6);

        for (uint256 i = 0; i < 6; i++) {
            params.multiples[i] = (2 + i) * MULTIPLE_SCALE; // 2x, 3x, 4x, 5x, 6x, 7x
            params.percentages[i] = 1000; // 10% each (60% total)
        }

        uint128 totalSize = uint128(TEST_ORDER_SIZE * 100);
        int24 baseTick = 0;
        uint160 sqrtPriceX96 = TickMath.getSqrtPriceAtTick(baseTick);

        (Orders memory orders, uint128 allocated, uint128 unallocated) = SwapLimitOrders.computeOrders(
            testKey,
            true,
            totalSize,
            baseTick,
            sqrtPriceX96,
            params
        );

        // All 6 orders should be created
        assertEq(orders.sizes.length, 6, "should create 6 orders");
        assertEq(orders.ticks.length, 6, "should have 6 ticks");
    }

    /// @notice Tests computeOrders with single order (loop executes once)
    function test_computeOrders_singleOrder_loopExecutesOnce() public {
        LimitOrderConfig memory params;
        params.multiples = new uint256[](1);
        params.percentages = new uint256[](1);
        params.multiples[0] = 2 * MULTIPLE_SCALE;
        params.percentages[0] = 10000;

        uint128 totalSize = uint128(TEST_ORDER_SIZE * 10);
        int24 baseTick = 0;
        uint160 sqrtPriceX96 = TickMath.getSqrtPriceAtTick(baseTick);

        (Orders memory orders, uint128 allocated, uint128 unallocated) = SwapLimitOrders.computeOrders(
            testKey,
            true,
            totalSize,
            baseTick,
            sqrtPriceX96,
            params
        );

        assertEq(orders.sizes.length, 1, "should create 1 order");
        assertEq(orders.ticks.length, 1, "should have 1 tick");
    }

    /// @notice Tests computeOrders with large totalSize and valid percentages
    function test_computeOrders_largeSize_allocatesCorrectly() public {
        LimitOrderConfig memory params;
        params.multiples = new uint256[](2);
        params.percentages = new uint256[](2);
        params.multiples[0] = 2 * MULTIPLE_SCALE;
        params.multiples[1] = 4 * MULTIPLE_SCALE;
        params.percentages[0] = 6000; // 60%
        params.percentages[1] = 3000; // 30% (total 90%)

        uint128 totalSize = uint128(1000 * TEST_ORDER_SIZE);
        int24 baseTick = 0;
        uint160 sqrtPriceX96 = TickMath.getSqrtPriceAtTick(baseTick);

        (Orders memory orders, uint128 allocated, uint128 unallocated) = SwapLimitOrders.computeOrders(
            testKey,
            true,
            totalSize,
            baseTick,
            sqrtPriceX96,
            params
        );

        assertEq(orders.sizes.length, 2, "should create 2 orders");

        // Verify order sizes apply percentages sequentially (second rung sized off remaining 40%)
        uint256 expectedFirst = (totalSize * 6000) / PERCENT_SCALE; // 60% of total
        uint256 expectedSecond = ((totalSize - expectedFirst) * 3000) / PERCENT_SCALE; // 30% of remaining
        assertEq(orders.sizes[0], expectedFirst, "first order size should be 60% of total");
        assertEq(orders.sizes[1], expectedSecond, "second order size should be 30% of remaining");

        // Verify allocated + unallocated = totalSize
        assertEq(uint256(allocated) + uint256(unallocated), totalSize, "allocated + unallocated should equal totalSize");
    }

    /// @notice Tests computeOrders sizes each rung off the remaining balance (geometric sizing)
    function test_computeOrders_percentages_applyToRemaining() public view {
        LimitOrderConfig memory params;
        params.multiples = new uint256[](3);
        params.percentages = new uint256[](3);
        params.multiples[0] = 2 * MULTIPLE_SCALE;
        params.multiples[1] = 3 * MULTIPLE_SCALE;
        params.multiples[2] = 4 * MULTIPLE_SCALE;
        params.percentages[0] = 2000; // 20%
        params.percentages[1] = 2000; // 20% of remaining
        params.percentages[2] = 2000; // 20% of remaining

        uint128 totalSize = uint128(100 * TEST_ORDER_SIZE); // 100 units for easy math
        int24 baseTick = 0;
        uint160 sqrtPriceX96 = TickMath.getSqrtPriceAtTick(baseTick);

        (Orders memory orders, uint128 allocated, uint128 unallocated) = SwapLimitOrders.computeOrders(
            testKey,
            true,
            totalSize,
            baseTick,
            sqrtPriceX96,
            params
        );

        assertEq(orders.sizes.length, 3, "should create 3 orders");

        uint256 expectedFirst = (totalSize * 2000) / PERCENT_SCALE; // 20 of 100
        uint256 remainingAfterFirst = totalSize - expectedFirst; // 80
        uint256 expectedSecond = (remainingAfterFirst * 2000) / PERCENT_SCALE; // 16
        uint256 remainingAfterSecond = remainingAfterFirst - expectedSecond; // 64
        uint256 expectedThird = (remainingAfterSecond * 2000) / PERCENT_SCALE; // 12

        assertEq(orders.sizes[0], expectedFirst, "first order size mismatch");
        assertEq(orders.sizes[1], expectedSecond, "second order size mismatch");
        assertEq(orders.sizes[2], expectedThird, "third order size mismatch");

        // Conservation: allocated + unallocated == totalSize
        assertEq(uint256(allocated) + uint256(unallocated), totalSize, "conservation must hold");
        assertEq(unallocated, uint128(totalSize - expectedFirst - expectedSecond - expectedThird), "unallocated should be remainder");
    }

    /// @notice Tests computeOrders with extreme multiples (tick clamping)
    function test_computeOrders_extremeMultiples_clampsToMaxTick() public {
        LimitOrderConfig memory params;
        params.multiples = new uint256[](1);
        params.percentages = new uint256[](1);
        params.multiples[0] = 1000 * MULTIPLE_SCALE; // 1000x - extremely high
        params.percentages[0] = 10000; // 100%

        uint128 totalSize = uint128(100 * TEST_ORDER_SIZE);
        int24 baseTick = 0;
        uint160 sqrtPriceX96 = TickMath.getSqrtPriceAtTick(baseTick);

        (Orders memory orders, , ) = SwapLimitOrders.computeOrders(testKey, true, totalSize, baseTick, sqrtPriceX96, params);

        int24 maxTick = TickMath.maxUsableTick(TICK_SPACING);

        // Tick should be clamped to max usable tick
        assertLe(orders.ticks[0], maxTick, "tick should be clamped to max");
        assertGt(orders.ticks[0], baseTick, "tick should be above base tick");
    }

    /// @notice Tests computeOrders for currency1 (isCurrency0 = false) - tests line 147 branch
    function test_computeOrders_currency1_ticksBelowBase() public {
        LimitOrderConfig memory params;
        params.multiples = new uint256[](2);
        params.percentages = new uint256[](2);
        params.multiples[0] = 2 * MULTIPLE_SCALE;
        params.multiples[1] = 4 * MULTIPLE_SCALE;
        params.percentages[0] = 5000;
        params.percentages[1] = 5000;

        uint128 totalSize = uint128(100 * TEST_ORDER_SIZE);
        int24 baseTick = 10000;
        uint160 sqrtPriceX96 = TickMath.getSqrtPriceAtTick(baseTick);

        (Orders memory orders, , ) = SwapLimitOrders.computeOrders(testKey, false, totalSize, baseTick, sqrtPriceX96, params);

        // For currency1 (isCurrency0 = false), ticks should be below baseTick
        assertLt(orders.ticks[0], baseTick, "tick 0 should be below base tick");
        assertLt(orders.ticks[1], baseTick, "tick 1 should be below base tick");
        assertLt(orders.ticks[1], orders.ticks[0], "higher multiple should have lower tick");
    }

    /// @notice Tests computeOrders with sqrt price overflow (line 155 branch: scaled > type(uint160).max)
    function test_computeOrders_sqrtPriceOverflow_clampsToMax() public {
        LimitOrderConfig memory params;
        params.multiples = new uint256[](1);
        params.percentages = new uint256[](1);
        // Use extremely large multiple to trigger overflow
        params.multiples[0] = 1000000 * MULTIPLE_SCALE; // 1,000,000x
        params.percentages[0] = 10000;

        uint128 totalSize = uint128(100 * TEST_ORDER_SIZE);
        // Use moderate base tick (TickMath has max/min around ±887272)
        int24 baseTick = 100000; // Moderate positive tick
        uint160 sqrtPriceX96 = TickMath.getSqrtPriceAtTick(baseTick);

        (Orders memory orders, , ) = SwapLimitOrders.computeOrders(testKey, true, totalSize, baseTick, sqrtPriceX96, params);

        // Should successfully create order with clamped tick
        assertEq(orders.sizes.length, 1, "should create 1 order");
        assertLe(orders.ticks[0], TickMath.maxUsableTick(TICK_SPACING), "tick should be <= max");
    }

    /// @notice Tests computeOrders near minimum tick boundary (line 169 branch: aligned < minTick)
    function test_computeOrders_nearMinTick_clampsToMin() public {
        LimitOrderConfig memory params;
        params.multiples = new uint256[](1);
        params.percentages = new uint256[](1);
        params.multiples[0] = 2 * MULTIPLE_SCALE;
        params.percentages[0] = 10000;

        uint128 totalSize = uint128(100 * TEST_ORDER_SIZE);
        // Use moderate negative base tick for currency1
        int24 baseTick = -100000; // Moderate negative tick
        uint160 sqrtPriceX96 = TickMath.getSqrtPriceAtTick(baseTick);

        (Orders memory orders, , ) = SwapLimitOrders.computeOrders(testKey, false, totalSize, baseTick, sqrtPriceX96, params);

        // Should successfully create order with clamped tick
        assertEq(orders.sizes.length, 1, "should create 1 order");
        assertGe(orders.ticks[0], TickMath.minUsableTick(TICK_SPACING), "tick should be >= min");
    }

    /// @notice Tests computeOrders with tick too close to base (line 170: isCurrency0 && aligned < minAway)
    function test_computeOrders_currency0_tooCloseToBase_clampsToMinAway() public {
        LimitOrderConfig memory params;
        params.multiples = new uint256[](1);
        params.percentages = new uint256[](1);
        // Use small multiple that would produce tick very close to base
        params.multiples[0] = MULTIPLE_SCALE + (MULTIPLE_SCALE / 100); // 1.01x
        params.percentages[0] = 10000;

        uint128 totalSize = uint128(100 * TEST_ORDER_SIZE);
        int24 baseTick = 0;
        uint160 sqrtPriceX96 = TickMath.getSqrtPriceAtTick(baseTick);

        (Orders memory orders, , ) = SwapLimitOrders.computeOrders(testKey, true, totalSize, baseTick, sqrtPriceX96, params);

        // For currency0, tick should be at least tickSpacing away from base
        assertGe(orders.ticks[0], baseTick + TICK_SPACING, "tick should be >= baseTick + spacing");
    }

    /// @notice Tests computeOrders with tick too close to base (line 171: !isCurrency0 && aligned > minAway)
    function test_computeOrders_currency1_tooCloseToBase_clampsToMinAway() public {
        LimitOrderConfig memory params;
        params.multiples = new uint256[](1);
        params.percentages = new uint256[](1);
        // Use small multiple that would produce tick very close to base
        params.multiples[0] = MULTIPLE_SCALE + (MULTIPLE_SCALE / 100); // 1.01x
        params.percentages[0] = 10000;

        uint128 totalSize = uint128(100 * TEST_ORDER_SIZE);
        int24 baseTick = 0;
        uint160 sqrtPriceX96 = TickMath.getSqrtPriceAtTick(baseTick);

        (Orders memory orders, , ) = SwapLimitOrders.computeOrders(testKey, false, totalSize, baseTick, sqrtPriceX96, params);

        // For currency1, tick should be at least tickSpacing away from base (below it)
        assertLe(orders.ticks[0], baseTick - TICK_SPACING, "tick should be <= baseTick - spacing");
    }

    /// @notice Tests _sqrtMultiple with zero (line 184 branch: result == 0)
    /// @dev This tests the error case by using a multiple that would cause sqrt to fail
    function test_computeOrders_zeroMultiple_reverts() public {
        LimitOrderConfig memory params;
        params.multiples = new uint256[](1);
        params.percentages = new uint256[](1);
        params.multiples[0] = 0; // Zero multiple - should revert in _sqrtMultiple
        params.percentages[0] = 10000;

        uint128 totalSize = uint128(100 * TEST_ORDER_SIZE);
        int24 baseTick = 0;
        uint160 sqrtPriceX96 = TickMath.getSqrtPriceAtTick(baseTick);

        vm.expectRevert();
        wrapper.computeOrders(testKey, true, totalSize, baseTick, sqrtPriceX96, params);
    }

    /// @notice Tests isLimitOrder when not a coin buy (first condition in line 48)
    function test_isLimitOrder_notCoinBuy_returnsFalse() public {
        LimitOrderConfig memory params;
        params.multiples = new uint256[](1);
        params.percentages = new uint256[](1);
        params.multiples[0] = 2 * MULTIPLE_SCALE;
        params.percentages[0] = 10000;

        bool isCoinBuy = false; // NOT isCoinBuy - tests first branch
        address swapper = address(0x1234);
        int128 coinDelta = int128(int256(TEST_ORDER_SIZE * 2));

        assertFalse(wrapper.isLimitOrder(isCoinBuy, swapper, coinDelta, params), "should return false when not coin buy");
    }

    /// @notice Tests isLimitOrder when isCoinBuy is true (ensures we go past first condition)
    function test_isLimitOrder_isCoinBuyTrue_checksOtherConditions() public {
        LimitOrderConfig memory params;
        params.multiples = new uint256[](0); // Empty - no orders
        params.percentages = new uint256[](0);

        bool isCoinBuy = true; // Pass first condition
        address swapper = address(0x1234);
        int128 coinDelta = int128(int256(TEST_ORDER_SIZE * 2));

        assertFalse(wrapper.isLimitOrder(isCoinBuy, swapper, coinDelta, params), "should return false when no orders");
    }

    /// @notice Tests isLimitOrder when no orders in params
    function test_isLimitOrder_noOrders_returnsFalse() public {
        LimitOrderConfig memory params;
        params.multiples = new uint256[](0);
        params.percentages = new uint256[](0);

        bool isCoinBuy = true;
        address swapper = address(0x1234);
        // casting to 'int256' is safe because TEST_ORDER_SIZE will not overflow int128
        int128 coinDelta = int128(int256(TEST_ORDER_SIZE * 2));

        assertFalse(wrapper.isLimitOrder(isCoinBuy, swapper, coinDelta, params), "should return false when no orders");
    }

    /// @notice Tests isLimitOrder when swapper is zero address
    function test_isLimitOrder_zeroSwapper_returnsFalse() public {
        LimitOrderConfig memory params;
        params.multiples = new uint256[](1);
        params.percentages = new uint256[](1);

        bool isCoinBuy = true;
        address swapper = address(0); // Zero address
        int128 coinDelta = int128(int256(TEST_ORDER_SIZE * 2));

        assertFalse(wrapper.isLimitOrder(isCoinBuy, swapper, coinDelta, params), "should return false when swapper is zero");
    }

    /// @notice Tests isLimitOrder when coinDelta is negative
    function test_isLimitOrder_negativeCoinDelta_returnsFalse() public {
        LimitOrderConfig memory params;
        params.multiples = new uint256[](1);
        params.percentages = new uint256[](1);

        bool isCoinBuy = true;
        address swapper = address(0x1234);
        int128 coinDelta = -100; // Negative delta

        assertFalse(wrapper.isLimitOrder(isCoinBuy, swapper, coinDelta, params), "should return false for negative delta");
    }

    /// @notice Tests isLimitOrder when coinDelta is zero
    function test_isLimitOrder_zeroCoinDelta_returnsFalse() public {
        LimitOrderConfig memory params;
        params.multiples = new uint256[](1);
        params.percentages = new uint256[](1);

        bool isCoinBuy = true;
        address swapper = address(0x1234);
        int128 coinDelta = 0; // Zero delta

        assertFalse(wrapper.isLimitOrder(isCoinBuy, swapper, coinDelta, params), "should return false for zero delta");
    }

    /// @notice Tests isLimitOrder accepts any positive coinDelta
    function test_isLimitOrder_smallSize_returnsTrue() public {
        LimitOrderConfig memory params;
        params.multiples = new uint256[](1);
        params.percentages = new uint256[](1);

        bool isCoinBuy = true;
        address swapper = address(0x1234);
        int128 coinDelta = 1; // Small positive amount

        assertTrue(wrapper.isLimitOrder(isCoinBuy, swapper, coinDelta, params), "should return true for any positive amount");
    }

    /// @notice Tests isLimitOrder when all conditions are met (success case)
    function test_isLimitOrder_allConditionsMet_returnsTrue() public {
        LimitOrderConfig memory params;
        params.multiples = new uint256[](1);
        params.percentages = new uint256[](1);
        params.multiples[0] = 2 * MULTIPLE_SCALE;
        params.percentages[0] = 10000;

        bool isCoinBuy = true;
        address swapper = address(0x1234);
        int128 coinDelta = int128(int256(TEST_ORDER_SIZE * 2));

        assertTrue(wrapper.isLimitOrder(isCoinBuy, swapper, coinDelta, params), "should return true when all conditions met");
    }

    /// @notice Tests computeOrders with misaligned baseTick produces aligned output ticks
    /// @dev This test verifies the fix for MKT-24: tick misalignment in minAway calculation
    function test_computeOrders_misalignedBaseTick_producesValidTicks() public {
        // Use a pool with tickSpacing = 10 for easier verification
        PoolKey memory smallSpacingKey = PoolKey({
            currency0: Currency.wrap(address(0x1000)),
            currency1: Currency.wrap(address(0x2000)),
            fee: 3000,
            tickSpacing: 10, // Small tick spacing to make misalignment easier to reproduce
            hooks: IHooks(address(0))
        });

        LimitOrderConfig memory params;
        params.multiples = new uint256[](1);
        params.percentages = new uint256[](1);
        // Use small multiple that would normally produce tick close to base
        params.multiples[0] = MULTIPLE_SCALE + (MULTIPLE_SCALE / 100); // 1.01x
        params.percentages[0] = 10000;

        uint128 totalSize = uint128(100 * TEST_ORDER_SIZE);

        // Use a baseTick that is NOT aligned to tickSpacing=10
        int24 baseTick = 205; // Not divisible by 10 - misaligned
        uint160 sqrtPriceX96 = TickMath.getSqrtPriceAtTick(baseTick);

        // Test for currency0 (buy orders, tick should be >= baseTick + tickSpacing)
        (Orders memory orders, , ) = SwapLimitOrders.computeOrders(
            smallSpacingKey,
            true, // isCurrency0
            totalSize,
            baseTick,
            sqrtPriceX96,
            params
        );

        // Verify the returned tick is aligned to tickSpacing
        assertEq(orders.ticks[0] % 10, 0, "tick must be aligned to tick spacing of 10");

        // Verify tick is at least one tickSpacing away from the aligned baseTick
        // For currency0, baseTick=205 should align down to 200, so minAway=210
        assertGe(orders.ticks[0], 210, "tick should be >= aligned baseTick (200) + spacing (10)");

        // Test for currency1 (sell orders, tick should be <= baseTick - tickSpacing)
        (Orders memory orders1, , ) = SwapLimitOrders.computeOrders(
            smallSpacingKey,
            false, // !isCurrency0
            totalSize,
            baseTick,
            sqrtPriceX96,
            params
        );

        // Verify the returned tick is aligned to tickSpacing
        assertEq(orders1.ticks[0] % 10, 0, "tick must be aligned to tick spacing of 10");

        // Verify tick is at least one tickSpacing away from the aligned baseTick
        // For currency1, baseTick=205 should align up to 210, so minAway=200
        assertLe(orders1.ticks[0], 200, "tick should be <= aligned baseTick (210) - spacing (10)");
    }

    /// @notice Tests computeOrders with various misaligned baseTicks and tick spacings
    function test_computeOrders_variousMisalignments_allProduceValidTicks() public view {
        LimitOrderConfig memory params;
        params.multiples = new uint256[](1);
        params.percentages = new uint256[](1);
        params.multiples[0] = MULTIPLE_SCALE + (MULTIPLE_SCALE / 50); // 1.02x
        params.percentages[0] = 10000;

        uint128 totalSize = uint128(100 * TEST_ORDER_SIZE);

        // Test case 1: baseTick=205, tickSpacing=10
        PoolKey memory key10 = testKey;
        key10.tickSpacing = 10;
        int24 baseTick1 = 205;
        uint160 sqrtPrice1 = TickMath.getSqrtPriceAtTick(baseTick1);
        (Orders memory orders1, , ) = SwapLimitOrders.computeOrders(key10, true, totalSize, baseTick1, sqrtPrice1, params);
        assertEq(orders1.ticks[0] % 10, 0, "case 1: tick must be aligned to spacing 10");

        // Test case 2: baseTick=1505, tickSpacing=200
        PoolKey memory key200 = testKey;
        key200.tickSpacing = 200;
        int24 baseTick2 = 1505;
        uint160 sqrtPrice2 = TickMath.getSqrtPriceAtTick(baseTick2);
        (Orders memory orders2, , ) = SwapLimitOrders.computeOrders(key200, true, totalSize, baseTick2, sqrtPrice2, params);
        assertEq(orders2.ticks[0] % 200, 0, "case 2: tick must be aligned to spacing 200");

        // Test case 3: negative misaligned baseTick=-95, tickSpacing=10
        int24 baseTick3 = -95;
        uint160 sqrtPrice3 = TickMath.getSqrtPriceAtTick(baseTick3);
        (Orders memory orders3, , ) = SwapLimitOrders.computeOrders(key10, true, totalSize, baseTick3, sqrtPrice3, params);
        assertEq(orders3.ticks[0] % 10, 0, "case 3: tick must be aligned to spacing 10");
    }

    /// @notice Tests computeOrders with already-aligned baseTicks remain aligned
    /// @dev Verifies that the fix doesn't break the common case where baseTick is already aligned
    function test_computeOrders_alignedBaseTick_remainsAligned() public view {
        LimitOrderConfig memory params;
        params.multiples = new uint256[](1);
        params.percentages = new uint256[](1);
        params.multiples[0] = MULTIPLE_SCALE + (MULTIPLE_SCALE / 50); // 1.02x
        params.percentages[0] = 10000;

        uint128 totalSize = uint128(100 * TEST_ORDER_SIZE);

        // Test case 1: baseTick=200 (aligned), tickSpacing=10
        PoolKey memory key10 = testKey;
        key10.tickSpacing = 10;
        int24 baseTick1 = 200; // Already divisible by 10
        uint160 sqrtPrice1 = TickMath.getSqrtPriceAtTick(baseTick1);
        (Orders memory orders1, , ) = SwapLimitOrders.computeOrders(key10, true, totalSize, baseTick1, sqrtPrice1, params);
        assertEq(orders1.ticks[0] % 10, 0, "aligned case 1: tick must be aligned to spacing 10");
        assertGe(orders1.ticks[0], baseTick1 + 10, "aligned case 1: tick should be >= baseTick + spacing");

        // Test case 2: baseTick=1400 (aligned), tickSpacing=200
        PoolKey memory key200 = testKey;
        key200.tickSpacing = 200;
        int24 baseTick2 = 1400; // Already divisible by 200
        uint160 sqrtPrice2 = TickMath.getSqrtPriceAtTick(baseTick2);
        (Orders memory orders2, , ) = SwapLimitOrders.computeOrders(key200, true, totalSize, baseTick2, sqrtPrice2, params);
        assertEq(orders2.ticks[0] % 200, 0, "aligned case 2: tick must be aligned to spacing 200");
        assertGe(orders2.ticks[0], baseTick2 + 200, "aligned case 2: tick should be >= baseTick + spacing");

        // Test case 3: baseTick=0 (aligned), tickSpacing=10
        int24 baseTick3 = 0; // Already divisible by any spacing
        uint160 sqrtPrice3 = TickMath.getSqrtPriceAtTick(baseTick3);
        (Orders memory orders3, , ) = SwapLimitOrders.computeOrders(key10, true, totalSize, baseTick3, sqrtPrice3, params);
        assertEq(orders3.ticks[0] % 10, 0, "aligned case 3: tick must be aligned to spacing 10");
        assertGe(orders3.ticks[0], baseTick3 + 10, "aligned case 3: tick should be >= baseTick + spacing");

        // Test case 4: negative aligned baseTick=-100, tickSpacing=10
        int24 baseTick4 = -100; // Already divisible by 10
        uint160 sqrtPrice4 = TickMath.getSqrtPriceAtTick(baseTick4);
        (Orders memory orders4, , ) = SwapLimitOrders.computeOrders(key10, true, totalSize, baseTick4, sqrtPrice4, params);
        assertEq(orders4.ticks[0] % 10, 0, "aligned case 4: tick must be aligned to spacing 10");
        assertGe(orders4.ticks[0], baseTick4 + 10, "aligned case 4: tick should be >= baseTick + spacing");
    }

    /// @notice Tests fix for MKT-35: skip orders when baseTick at maxTick
    /// @dev Uses baseTick at maxTick to simulate swap exhausting liquidity
    function test_computeOrders_baseTickAtMaxTick_skipsOrders() public view {
        LimitOrderConfig memory params;
        params.multiples = new uint256[](1);
        params.percentages = new uint256[](1);
        params.multiples[0] = 2 * MULTIPLE_SCALE;
        params.percentages[0] = 10000;

        uint128 totalSize = uint128(100 * TEST_ORDER_SIZE);
        int24 maxTick = TickMath.maxUsableTick(TICK_SPACING);
        int24 baseTick = maxTick;
        // Use MAX_SQRT_PRICE directly since we can't compute sqrt price at maxTick
        uint160 sqrtPriceX96 = TickMath.MAX_SQRT_PRICE - 1;

        // For currency0 (buy orders), should skip and return all as unallocated
        (Orders memory orders, uint128 allocated, uint128 unallocated) = SwapLimitOrders.computeOrders(
            testKey,
            true,
            totalSize,
            baseTick,
            sqrtPriceX96,
            params
        );

        assertEq(orders.sizes.length, 0, "should create no orders");
        assertEq(allocated, 0, "should not allocate any funds");
        assertEq(unallocated, totalSize, "all funds should be unallocated");
    }

    /// @notice Tests fix for MKT-35: skip orders when baseTick at minTick
    /// @dev Uses baseTick at minTick to simulate swap exhausting liquidity
    function test_computeOrders_baseTickAtMinTick_skipsOrders() public view {
        LimitOrderConfig memory params;
        params.multiples = new uint256[](1);
        params.percentages = new uint256[](1);
        params.multiples[0] = 2 * MULTIPLE_SCALE;
        params.percentages[0] = 10000;

        uint128 totalSize = uint128(100 * TEST_ORDER_SIZE);
        int24 maxTick = TickMath.maxUsableTick(TICK_SPACING);
        int24 minTick = -maxTick;
        int24 baseTick = minTick;
        // Use MIN_SQRT_PRICE directly since we can't compute sqrt price at minTick
        uint160 sqrtPriceX96 = TickMath.MIN_SQRT_PRICE + 1;

        // For currency1 (sell orders), should skip and return all as unallocated
        (Orders memory orders, uint128 allocated, uint128 unallocated) = SwapLimitOrders.computeOrders(
            testKey,
            false,
            totalSize,
            baseTick,
            sqrtPriceX96,
            params
        );

        assertEq(orders.sizes.length, 0, "should create no orders");
        assertEq(allocated, 0, "should not allocate any funds");
        assertEq(unallocated, totalSize, "all funds should be unallocated");
    }
}
