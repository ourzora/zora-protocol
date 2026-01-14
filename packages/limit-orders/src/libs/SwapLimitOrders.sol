// SPDX-License-Identifier: ZORA-DELAYED-OSL-v1
// This software is licensed under the Zora Delayed Open Source License.
// Under this license, you may use, copy, modify, and distribute this software for
// non-commercial purposes only. Commercial use and competitive products are prohibited
// until the "Open Date" (3 years from first public distribution or earlier at Zora's discretion),
// at which point this software automatically becomes available under the MIT License.
// Full license terms available at: https://docs.zora.co/coins/license
pragma solidity ^0.8.28;

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {TickMath} from "@zoralabs/coins/src/utils/uniswap/TickMath.sol";
import {FullMath} from "@zoralabs/coins/src/utils/uniswap/FullMath.sol";
import {DopplerMath} from "@zoralabs/coins/src/libs/DopplerMath.sol";

/// @dev Configuration for a limit order ladder
/// @param multiples Price multiples for each order (e.g., 2e18 = 2x current price)
/// @param percentages Percentage of total size for each order (basis points, must sum ≤ 10000)
struct LimitOrderConfig {
    uint256[] multiples;
    uint256[] percentages;
}

/// @dev Computed limit orders ready for execution
/// @param sizes Amount of coins in each order
/// @param ticks Uniswap tick for each order
/// @param multiples Price multiple used for each order (tracks which config entry)
/// @param percentages Percentage used for each order (tracks which config entry)
struct Orders {
    uint256[] sizes;
    int24[] ticks;
    uint256[] multiples;
    uint256[] percentages;
}

/// @title SwapLimitOrders
/// @notice Computes limit order ladders on coin swaps
library SwapLimitOrders {
    /// @dev 1.0x price multiplier (e.g., 2e18 = 2x)
    uint256 internal constant MULTIPLE_SCALE = 1e18;

    /// @dev 100% in basis points (e.g., 5000 = 50%)
    uint256 internal constant PERCENT_SCALE = 10_000;

    /// @dev sqrt(1e18) - scales sqrt calculations without precision loss
    uint256 internal constant SQRT_MULTIPLE_SCALE = 1e9;

    /// @notice Multiples and percentages arrays have different lengths
    error LengthMismatch();

    /// @notice Percentages sum exceeds 100%
    error PercentOverflow();

    /// @notice A percentage is zero
    error InvalidPercent();

    /// @notice A multiple is ≤ 1.0x
    error InvalidMultiple();

    /// @notice Validates a limit order configuration
    /// @param config The configuration to validate
    /// @return totalPercent Sum of all percentages (for caller's use)
    /// @dev Reverts if:
    ///      - Arrays are empty or mismatched length
    ///      - Any percentage is zero
    ///      - Any multiple is ≤ 1.0x
    ///      - Percentages sum > 100%
    function validate(LimitOrderConfig memory config) internal pure returns (uint256 totalPercent) {
        uint256 length = config.multiples.length;

        require(length > 0 && length == config.percentages.length, LengthMismatch());

        unchecked {
            for (uint256 i; i < length; ++i) {
                require(config.percentages[i] != 0, InvalidPercent());
                require(config.multiples[i] > MULTIPLE_SCALE, InvalidMultiple());
                totalPercent += config.percentages[i]; // Bounded by PERCENT_SCALE check below
            }
        }

        require(totalPercent <= PERCENT_SCALE, PercentOverflow());
    }

    /// @notice Computes limit order sizes and ticks from a configuration
    /// @param key The Uniswap pool
    /// @param isCurrency0 True if placing orders for currency0, false for currency1
    /// @param totalSize Total coins to distribute across orders
    /// @param baseTick Current pool tick (orders placed at least 1 tick spacing away)
    /// @param sqrtPriceX96 Current pool sqrt price
    /// @param config The limit order configuration
    /// @return o Orders ready for creation (may have fewer entries than config if some rounded to zero)
    /// @return allocated Amount of totalSize allocated to orders
    /// @return unallocated Amount of totalSize not allocated (dust or partial fill)
    /// @dev Orders are sized sequentially: each order takes its percentage of remaining balance.
    ///      Orders with zero size after rounding are skipped - arrays shrink to match.
    function computeOrders(
        PoolKey memory key,
        bool isCurrency0,
        uint128 totalSize,
        int24 baseTick,
        uint160 sqrtPriceX96,
        LimitOrderConfig memory config
    ) internal pure returns (Orders memory o, uint128 allocated, uint128 unallocated) {
        if (totalSize == 0) {
            return (o, allocated, unallocated);
        }

        // Skip order creation when at tick boundaries
        // For currency0 (buy orders): cannot place if baseTick is at maxTick
        // For currency1 (sell orders): cannot place if baseTick is at minTick
        int24 maxTick = TickMath.maxUsableTick(key.tickSpacing);
        int24 alignedBaseTick = DopplerMath.alignTickToTickSpacing(isCurrency0, baseTick, key.tickSpacing);

        if (isCurrency0 ? alignedBaseTick >= maxTick : alignedBaseTick <= -maxTick) {
            unallocated = totalSize;
            return (o, allocated, unallocated);
        }

        uint256 orderCount = config.multiples.length;

        o.sizes = new uint256[](orderCount);
        o.ticks = new int24[](orderCount);
        o.multiples = new uint256[](orderCount);
        o.percentages = new uint256[](orderCount);

        uint128 remaining = totalSize;
        uint256 count;

        for (uint256 i; i < orderCount; ++i) {
            uint256 orderSize = FullMath.mulDiv(uint256(remaining), config.percentages[i], PERCENT_SCALE);
            if (orderSize == 0) continue;

            allocated += uint128(orderSize);
            remaining -= uint128(orderSize);

            int24 targetTick = _tickForMultiple(key, isCurrency0, baseTick, sqrtPriceX96, config.multiples[i]);

            o.sizes[count] = orderSize;
            o.ticks[count] = targetTick;
            o.multiples[count] = config.multiples[i];
            o.percentages[count] = config.percentages[i];

            unchecked {
                ++count;
            }
        }

        assembly ("memory-safe") {
            // Shrink arrays in place so the caller only sees populated entries
            mstore(mload(o), count)
            mstore(mload(add(o, 0x20)), count)
            mstore(mload(add(o, 0x40)), count)
            mstore(mload(add(o, 0x60)), count)
        }

        unallocated = remaining;
    }

    /// @notice Converts a price multiple to a valid Uniswap tick
    /// @param key The pool (for tick spacing and bounds)
    /// @param isCurrency0 True for buys (tick > base), false for sells (tick < base)
    /// @param baseTick Current pool tick
    /// @param sqrtPriceX96 Current pool sqrt price
    /// @param multiple Desired price multiple (e.g., 2e18 = 2x)
    /// @return aligned Valid tick respecting spacing, bounds, and minimum separation from baseTick
    function _tickForMultiple(
        PoolKey memory key,
        bool isCurrency0,
        int24 baseTick,
        uint160 sqrtPriceX96,
        uint256 multiple
    ) private pure returns (int24 aligned) {
        require(multiple > MULTIPLE_SCALE, InvalidMultiple());

        uint256 sqrtMultiplier = _sqrtMultiple(multiple);
        if (!isCurrency0) {
            sqrtMultiplier = (SQRT_MULTIPLE_SCALE * SQRT_MULTIPLE_SCALE) / sqrtMultiplier;
        }

        uint256 scaled = FullMath.mulDiv(uint256(sqrtPriceX96), sqrtMultiplier, SQRT_MULTIPLE_SCALE);
        if (scaled > type(uint160).max) scaled = type(uint160).max;

        int24 rawTick = TickMath.getTickAtSqrtPrice(uint160(scaled));
        aligned = DopplerMath.alignTickToTickSpacing(isCurrency0, rawTick, key.tickSpacing);

        int24 maxTick = TickMath.maxUsableTick(key.tickSpacing);
        int24 minTick = -maxTick;

        if (aligned > maxTick) {
            aligned = maxTick;
        } else if (aligned < minTick) {
            aligned = minTick;
        }

        int24 alignedBaseTick = DopplerMath.alignTickToTickSpacing(isCurrency0, baseTick, key.tickSpacing);
        int24 minAway = alignedBaseTick + (isCurrency0 ? key.tickSpacing : -key.tickSpacing);
        if (isCurrency0) {
            if (aligned < minAway) aligned = minAway;
        } else {
            if (aligned > minAway) aligned = minAway;
        }
    }

    /// @notice Computes square root of a 1e18-scaled value using Babylonian method
    /// @param multiple Value to take sqrt of (e.g., 4e18 → 2e9)
    /// @return result Square root with 1e9 scaling
    /// @dev Uses iterative approximation: x_next = (x + multiple/x) / 2
    function _sqrtMultiple(uint256 multiple) private pure returns (uint256 result) {
        result = multiple;
        uint256 x = (multiple + 1) >> 1;
        while (x < result) {
            result = x;
            x = (multiple / x + x) >> 1;
        }
        require(result != 0, InvalidMultiple());
    }
}
