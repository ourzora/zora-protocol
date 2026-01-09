// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {LimitOrderBitmap} from "../../src/libs/LimitOrderBitmap.sol";
import {LimitOrderTypes} from "../../src/libs/LimitOrderTypes.sol";
import {TickBitmap} from "@uniswap/v4-core/src/libraries/TickBitmap.sol";

/// @notice Direct unit tests for LimitOrderBitmap library functions
contract LimitOrderBitmapUnitTest is Test {
    using LimitOrderBitmap for mapping(int16 => uint256);

    mapping(int16 => uint256) internal bitmap;
    mapping(int24 => LimitOrderTypes.Queue) internal poolQueue;

    int24 constant TICK_SPACING = 200;

    function setUp() public {
        // Clear bitmap before each test
        // Note: Can't easily clear all, but tests use fresh ticks
    }

    /// @notice Tests setIfFirst when sizeBefore is 0 (should set bit)
    function test_setIfFirst_zeroSizeBefore_setsBit() public {
        int24 tick = 1000;
        uint256 sizeBefore = 0; // First order at this tick

        // Verify bit not set initially
        assertFalse(_isTickSet(tick), "bit should not be set initially");

        // Call setIfFirst with sizeBefore = 0
        LimitOrderBitmap.setIfFirst(bitmap, tick, TICK_SPACING, sizeBefore);

        // Verify bit is now set
        assertTrue(_isTickSet(tick), "bit should be set after setIfFirst");
    }

    /// @notice Tests setIfFirst when sizeBefore > 0 (should NOT set bit)
    function test_setIfFirst_nonZeroSizeBefore_doesNotSetBit() public {
        int24 tick = 2000;
        uint256 sizeBefore = 100; // Already has orders

        // Verify bit not set initially
        assertFalse(_isTickSet(tick), "bit should not be set initially");

        // Call setIfFirst with sizeBefore > 0
        LimitOrderBitmap.setIfFirst(bitmap, tick, TICK_SPACING, sizeBefore);

        // Verify bit is still not set (early return path)
        assertFalse(_isTickSet(tick), "bit should not be set when sizeBefore > 0");
    }

    /// @notice Tests clearIfEmpty when sizeAfter is 0 (should clear bit)
    function test_clearIfEmpty_zeroSizeAfter_clearsBit() public {
        int24 tick = 3000;

        // First set the bit
        LimitOrderBitmap.setIfFirst(bitmap, tick, TICK_SPACING, 0);
        assertTrue(_isTickSet(tick), "bit should be set initially");

        // Call clearIfEmpty with sizeAfter = 0
        uint256 sizeAfter = 0; // No more orders at this tick
        LimitOrderBitmap.clearIfEmpty(bitmap, tick, TICK_SPACING, sizeAfter);

        // Verify bit is cleared
        assertFalse(_isTickSet(tick), "bit should be cleared after clearIfEmpty");
    }

    /// @notice Tests clearIfEmpty when sizeAfter > 0 (should NOT clear bit)
    function test_clearIfEmpty_nonZeroSizeAfter_doesNotClearBit() public {
        int24 tick = 4000;

        // First set the bit
        LimitOrderBitmap.setIfFirst(bitmap, tick, TICK_SPACING, 0);
        assertTrue(_isTickSet(tick), "bit should be set initially");

        // Call clearIfEmpty with sizeAfter > 0
        uint256 sizeAfter = 50; // Still has orders
        LimitOrderBitmap.clearIfEmpty(bitmap, tick, TICK_SPACING, sizeAfter);

        // Verify bit is still set (early return path)
        assertTrue(_isTickSet(tick), "bit should remain set when sizeAfter > 0");
    }

    /// @notice Tests getExecutableTicks with zeroForOne = true (downward price movement)
    function test_getExecutableTicks_zeroForOne_findsInitializedTicks() public {
        // Set up ticks: 10000, 10200, 10400 (spaced by TICK_SPACING)
        int24 tick1 = 10000;
        int24 tick2 = 10200;
        int24 tick3 = 10400;

        LimitOrderBitmap.setIfFirst(bitmap, tick1, TICK_SPACING, 0);
        LimitOrderBitmap.setIfFirst(bitmap, tick2, TICK_SPACING, 0);
        LimitOrderBitmap.setIfFirst(bitmap, tick3, TICK_SPACING, 0);

        // Set queue lengths to non-zero (simulates orders exist)
        poolQueue[tick1].length = 1;
        poolQueue[tick2].length = 1;
        poolQueue[tick3].length = 1;

        // Swap from 10800 down to 9800 (crosses all three ticks)
        int24 tickBefore = 10800;
        int24 tickAfter = 9800;
        bool zeroForOne = true;

        int24[] memory executableTicks = LimitOrderBitmap.getExecutableTicks(bitmap, poolQueue, TICK_SPACING, zeroForOne, tickBefore, tickAfter);

        // Should find all 3 initialized ticks
        assertEq(executableTicks.length, 3, "should find 3 executable ticks");
        assertEq(executableTicks[0], tick3, "should find tick3 first (highest)");
        assertEq(executableTicks[1], tick2, "should find tick2 second");
        assertEq(executableTicks[2], tick1, "should find tick1 last (lowest)");
    }

    /// @notice Tests getExecutableTicks with zeroForOne = false (upward price movement)
    function test_getExecutableTicks_oneForZero_findsInitializedTicks() public {
        // Set up ticks: 5000, 5200, 5400
        int24 tick1 = 5000;
        int24 tick2 = 5200;
        int24 tick3 = 5400;

        LimitOrderBitmap.setIfFirst(bitmap, tick1, TICK_SPACING, 0);
        LimitOrderBitmap.setIfFirst(bitmap, tick2, TICK_SPACING, 0);
        LimitOrderBitmap.setIfFirst(bitmap, tick3, TICK_SPACING, 0);

        poolQueue[tick1].length = 1;
        poolQueue[tick2].length = 1;
        poolQueue[tick3].length = 1;

        // Swap from 4800 up to 5600 (crosses all three ticks)
        int24 tickBefore = 4800;
        int24 tickAfter = 5600;
        bool zeroForOne = false;

        int24[] memory executableTicks = LimitOrderBitmap.getExecutableTicks(bitmap, poolQueue, TICK_SPACING, zeroForOne, tickBefore, tickAfter);

        // Should find all 3 initialized ticks in ascending order
        assertEq(executableTicks.length, 3, "should find 3 executable ticks");
        assertEq(executableTicks[0], tick1, "should find tick1 first (lowest)");
        assertEq(executableTicks[1], tick2, "should find tick2 second");
        assertEq(executableTicks[2], tick3, "should find tick3 last (highest)");
    }

    /// @notice Tests getExecutableTicks skips ticks with empty queues
    function test_getExecutableTicks_skipsEmptyQueues() public {
        // Set up 3 ticks, but only 2 have orders
        int24 tick1 = 6000;
        int24 tick2 = 6200; // This one will have empty queue
        int24 tick3 = 6400;

        LimitOrderBitmap.setIfFirst(bitmap, tick1, TICK_SPACING, 0);
        LimitOrderBitmap.setIfFirst(bitmap, tick2, TICK_SPACING, 0);
        LimitOrderBitmap.setIfFirst(bitmap, tick3, TICK_SPACING, 0);

        poolQueue[tick1].length = 1;
        poolQueue[tick2].length = 0; // Empty queue - should skip
        poolQueue[tick3].length = 1;

        int24 tickBefore = 6600;
        int24 tickAfter = 5800;
        bool zeroForOne = true;

        int24[] memory executableTicks = LimitOrderBitmap.getExecutableTicks(bitmap, poolQueue, TICK_SPACING, zeroForOne, tickBefore, tickAfter);

        // Should find only 2 ticks (skip tick2 with empty queue)
        assertEq(executableTicks.length, 2, "should find only 2 executable ticks");
        assertEq(executableTicks[0], tick3, "should find tick3");
        assertEq(executableTicks[1], tick1, "should find tick1");
        // tick2 should not be in the array
    }

    /// @notice Tests getExecutableTicks with no movement (tickBefore == tickAfter)
    function test_getExecutableTicks_noMovement_returnsEmpty() public {
        int24 tick = 7000;
        LimitOrderBitmap.setIfFirst(bitmap, tick, TICK_SPACING, 0);
        poolQueue[tick].length = 1;

        int24 tickBefore = 7000;
        int24 tickAfter = 7000; // No movement
        bool zeroForOne = true;

        int24[] memory executableTicks = LimitOrderBitmap.getExecutableTicks(bitmap, poolQueue, TICK_SPACING, zeroForOne, tickBefore, tickAfter);

        // Should return empty array (no ticks crossed)
        assertEq(executableTicks.length, 0, "should return empty array for no movement");
    }

    /// @notice Tests getExecutableTicks stops at target even if more ticks initialized beyond
    function test_getExecutableTicks_stopsAtTarget() public {
        // Set up ticks: 8000, 8200, 8400, 8600
        int24 tick1 = 8000;
        int24 tick2 = 8200;
        int24 tick3 = 8400;
        int24 tick4 = 8600;

        LimitOrderBitmap.setIfFirst(bitmap, tick1, TICK_SPACING, 0);
        LimitOrderBitmap.setIfFirst(bitmap, tick2, TICK_SPACING, 0);
        LimitOrderBitmap.setIfFirst(bitmap, tick3, TICK_SPACING, 0);
        LimitOrderBitmap.setIfFirst(bitmap, tick4, TICK_SPACING, 0);

        poolQueue[tick1].length = 1;
        poolQueue[tick2].length = 1;
        poolQueue[tick3].length = 1;
        poolQueue[tick4].length = 1;

        // Swap only crosses tick4 and tick3, stops before tick2
        int24 tickBefore = 8800;
        int24 tickAfter = 8300; // Stops between tick3 and tick2
        bool zeroForOne = true;

        int24[] memory executableTicks = LimitOrderBitmap.getExecutableTicks(bitmap, poolQueue, TICK_SPACING, zeroForOne, tickBefore, tickAfter);

        // Should find only tick4 and tick3 (stops at target)
        assertEq(executableTicks.length, 2, "should find only 2 ticks before target");
        assertEq(executableTicks[0], tick4, "should find tick4");
        assertEq(executableTicks[1], tick3, "should find tick3");
    }

    /// @notice Tests word boundaries (ticks at 256 * spacing intervals)
    function test_setIfFirst_wordBoundary() public {
        // Ticks at word boundaries
        int24 tick1 = 0; // word 0, bit 0
        int24 tick2 = 255 * TICK_SPACING; // word 0, bit 255
        int24 tick3 = 256 * TICK_SPACING; // word 1, bit 0
        int24 tick4 = -256 * TICK_SPACING; // word -1, bit 0

        // Set all at boundaries
        LimitOrderBitmap.setIfFirst(bitmap, tick1, TICK_SPACING, 0);
        LimitOrderBitmap.setIfFirst(bitmap, tick2, TICK_SPACING, 0);
        LimitOrderBitmap.setIfFirst(bitmap, tick3, TICK_SPACING, 0);
        LimitOrderBitmap.setIfFirst(bitmap, tick4, TICK_SPACING, 0);

        // Verify all set
        assertTrue(_isTickSet(tick1), "tick1 should be set");
        assertTrue(_isTickSet(tick2), "tick2 should be set");
        assertTrue(_isTickSet(tick3), "tick3 should be set");
        assertTrue(_isTickSet(tick4), "tick4 should be set");

        // Clear all
        LimitOrderBitmap.clearIfEmpty(bitmap, tick1, TICK_SPACING, 0);
        LimitOrderBitmap.clearIfEmpty(bitmap, tick2, TICK_SPACING, 0);
        LimitOrderBitmap.clearIfEmpty(bitmap, tick3, TICK_SPACING, 0);
        LimitOrderBitmap.clearIfEmpty(bitmap, tick4, TICK_SPACING, 0);

        // Verify all cleared
        assertFalse(_isTickSet(tick1), "tick1 should be cleared");
        assertFalse(_isTickSet(tick2), "tick2 should be cleared");
        assertFalse(_isTickSet(tick3), "tick3 should be cleared");
        assertFalse(_isTickSet(tick4), "tick4 should be cleared");
    }

    /// @notice Tests negative ticks
    function test_setIfFirst_negativeTicks() public {
        int24 tick1 = -5000;
        int24 tick2 = -10000;

        LimitOrderBitmap.setIfFirst(bitmap, tick1, TICK_SPACING, 0);
        LimitOrderBitmap.setIfFirst(bitmap, tick2, TICK_SPACING, 0);

        assertTrue(_isTickSet(tick1), "negative tick1 should be set");
        assertTrue(_isTickSet(tick2), "negative tick2 should be set");

        LimitOrderBitmap.clearIfEmpty(bitmap, tick1, TICK_SPACING, 0);
        LimitOrderBitmap.clearIfEmpty(bitmap, tick2, TICK_SPACING, 0);

        assertFalse(_isTickSet(tick1), "negative tick1 should be cleared");
        assertFalse(_isTickSet(tick2), "negative tick2 should be cleared");
    }

    function _isTickSet(int24 tick) internal view returns (bool) {
        int24 compressed = TickBitmap.compress(tick, TICK_SPACING);
        (int16 wordPos, uint8 bitPos) = TickBitmap.position(compressed);
        uint256 word = bitmap[wordPos];
        return (word & (1 << bitPos)) != 0;
    }
}
