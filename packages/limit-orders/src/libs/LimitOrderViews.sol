// SPDX-License-Identifier: ZORA-DELAYED-OSL-v1
// This software is licensed under the Zora Delayed Open Source License.
// Under this license, you may use, copy, modify, and distribute this software for
// non-commercial purposes only. Commercial use and competitive products are prohibited
// until the "Open Date" (3 years from first public distribution or earlier at Zora's discretion),
// at which point this software automatically becomes available under the MIT License.
// Full license terms available at: https://docs.zora.co/coins/license
pragma solidity ^0.8.28;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {LiquidityAmounts} from "@zoralabs/coins/src/utils/uniswap/LiquidityAmounts.sol";

import {LimitOrderStorage} from "./LimitOrderStorage.sol";
import {IZoraLimitOrderBook} from "../IZoraLimitOrderBook.sol";
import {CoinCommon} from "@zoralabs/coins/src/libs/CoinCommon.sol";

/// @title LimitOrderViews
/// @notice External library for view/pure functions to reduce contract size via library linking
library LimitOrderViews {
    using PoolIdLibrary for PoolKey;

    int24 internal constant TICK_SENTINEL = type(int24).max;

    /// @notice Snaps the current pool tick to the nearest aligned tick and returns its neighbors.
    /// @dev Uniswap v4 ticks must lie on multiples of `tickSpacing`. We round the live
    ///      tick down to the nearest aligned value (handling negatives), clamp it inside
    ///      the pool's usable range, then compute the next/previous aligned ticks for
    ///      callers that need to build deterministic tick windows.
    function _alignedTicks(
        IPoolManager poolManager,
        PoolKey memory key,
        int24 spacing
    ) private view returns (int24 anchorTick, int24 nextAligned, int24 prevAligned) {
        (, int24 currentTick, , ) = StateLibrary.getSlot0(poolManager, key.toId());
        int256 remainder;
        assembly ("memory-safe") {
            remainder := smod(currentTick, spacing)
        }

        if (remainder == 0) {
            anchorTick = currentTick;
        } else if (currentTick >= 0) {
            anchorTick = int24(int256(currentTick) - remainder);
        } else {
            anchorTick = int24(int256(currentTick) - remainder - spacing);
        }

        int24 minUsable = TickMath.minUsableTick(spacing);
        int24 maxUsable = TickMath.maxUsableTick(spacing);

        if (anchorTick < minUsable) {
            anchorTick = minUsable;
        } else if (anchorTick > maxUsable) {
            anchorTick = maxUsable;
        }

        nextAligned = anchorTick + spacing;
        if (nextAligned > maxUsable) {
            nextAligned = maxUsable;
        }

        prevAligned = anchorTick - spacing;
        if (prevAligned < minUsable) {
            prevAligned = minUsable;
        }
    }

    /// @notice Calculate liquidity for a limit order given size and tick range.
    /// @param isCurrency0 Whether the order is for currency0.
    /// @param size The size of the order.
    /// @param tickLower Lower tick of the position.
    /// @param tickUpper Upper tick of the position.
    /// @return The liquidity amount for the order.
    function liquidityForOrder(bool isCurrency0, uint256 size, int24 tickLower, int24 tickUpper) external pure returns (uint128) {
        uint160 sqrtPriceLower = TickMath.getSqrtPriceAtTick(tickLower);
        uint160 sqrtPriceUpper = TickMath.getSqrtPriceAtTick(tickUpper);
        return
            isCurrency0
                ? LiquidityAmounts.getLiquidityForAmount0(sqrtPriceLower, sqrtPriceUpper, size)
                : LiquidityAmounts.getLiquidityForAmount1(sqrtPriceLower, sqrtPriceUpper, size);
    }

    /// @notice Validates and resolves tick range for fill operations.
    /// @param state The limit order storage layout.
    /// @param poolManager The Uniswap v4 pool manager.
    /// @param providedKey The pool key provided by the caller.
    /// @param isCurrency0 Whether targeting currency0 orders.
    /// @param startTick User-provided start tick or sentinel.
    /// @param endTick User-provided end tick or sentinel.
    /// @return canonicalKey The canonical pool key from storage or provided key.
    /// @return resolvedStart Concrete start tick after resolving sentinels.
    /// @return resolvedEnd Concrete end tick after resolving sentinels.
    function validateTickRange(
        LimitOrderStorage.Layout storage state,
        IPoolManager poolManager,
        PoolKey calldata providedKey,
        bool isCurrency0,
        int24 startTick,
        int24 endTick
    ) external view returns (PoolKey memory canonicalKey, int24 resolvedStart, int24 resolvedEnd) {
        bytes32 poolKeyHash = CoinCommon.hashPoolKey(providedKey);
        canonicalKey = state.poolKeys[poolKeyHash];
        if (canonicalKey.tickSpacing == 0) {
            canonicalKey = providedKey;
            if (canonicalKey.tickSpacing == 0) revert IZoraLimitOrderBook.InvalidPoolKey();
        }

        (resolvedStart, resolvedEnd) = _resolveTickRange(poolManager, canonicalKey, isCurrency0, startTick, endTick);
        _validateTickRange(isCurrency0, resolvedStart, resolvedEnd);
    }

    /// @notice Derives concrete tick bounds from user input and current pool state.
    /// @dev Callers may pass sentinel values (`-TICK_SENTINEL` / `TICK_SENTINEL`) to mean
    ///      "start at the current tick" or "extend one spacing away". This helper translates
    ///      those sentinels into real ticks by snapping to the pool's aligned tick grid and
    ///      offsetting one spacing in the appropriate direction so fills never include
    ///      orders created in the same transaction.
    function _resolveTickRange(
        IPoolManager poolManager,
        PoolKey memory key,
        bool isCurrency0,
        int24 startTick,
        int24 endTick
    ) private view returns (int24 resolvedStart, int24 resolvedEnd) {
        int24 spacing = key.tickSpacing;

        bool startSentinel = startTick == -TICK_SENTINEL;
        bool endSentinel = endTick == TICK_SENTINEL;

        (int24 anchorTick, int24 nextAligned, int24 prevAligned) = _alignedTicks(poolManager, key, spacing);

        if (startSentinel) {
            // Treat sentinel start as anchoring the window at the aligned tick.
            resolvedStart = anchorTick;
            resolvedEnd = endSentinel ? (isCurrency0 ? nextAligned : prevAligned) : endTick;
            return (resolvedStart, resolvedEnd);
        }

        if (endSentinel) {
            resolvedStart = startTick;
            resolvedEnd = isCurrency0 ? nextAligned : anchorTick;
            return (resolvedStart, resolvedEnd);
        }

        resolvedStart = startTick;
        resolvedEnd = endTick;
        return (resolvedStart, resolvedEnd);
    }

    function _validateTickRange(bool isCurrency0, int24 startTick, int24 endTick) private pure {
        if (startTick < TickMath.MIN_TICK || startTick > TickMath.MAX_TICK) {
            revert IZoraLimitOrderBook.InvalidFillWindow(startTick, endTick, isCurrency0);
        }
        if (endTick < TickMath.MIN_TICK || endTick > TickMath.MAX_TICK) {
            revert IZoraLimitOrderBook.InvalidFillWindow(startTick, endTick, isCurrency0);
        }

        if (isCurrency0) {
            if (startTick > endTick) revert IZoraLimitOrderBook.InvalidFillWindow(startTick, endTick, isCurrency0);
        } else {
            if (startTick < endTick) revert IZoraLimitOrderBook.InvalidFillWindow(startTick, endTick, isCurrency0);
        }
    }
}
