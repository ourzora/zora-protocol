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
