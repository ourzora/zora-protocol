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
import {TickBitmap} from "@uniswap/v4-core/src/libraries/TickBitmap.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

import {LimitOrderStorage} from "./LimitOrderStorage.sol";
import {IZoraLimitOrderBook} from "../IZoraLimitOrderBook.sol";
import {LimitOrderTypes} from "./LimitOrderTypes.sol";
import {LimitOrderLiquidity} from "./LimitOrderLiquidity.sol";
import {LimitOrderCommon} from "./LimitOrderCommon.sol";
import {CoinCommon} from "@zoralabs/coins/src/libs/CoinCommon.sol";
import {IDeployedCoinVersionLookup} from "@zoralabs/coins/src/interfaces/IDeployedCoinVersionLookup.sol";

library LimitOrderFill {
    using PoolIdLibrary for PoolKey;

    int24 internal constant TICK_SENTINEL = type(int24).max;

    struct Context {
        IPoolManager poolManager;
        IDeployedCoinVersionLookup versionLookup;
    }

    function validateTickRange(
        LimitOrderStorage.Layout storage state,
        Context memory ctx,
        PoolKey calldata providedKey,
        bool isCurrency0,
        int24 startTick,
        int24 endTick
    ) internal view returns (PoolKey memory canonicalKey, int24 resolvedStart, int24 resolvedEnd) {
        bytes32 poolKeyHash = CoinCommon.hashPoolKey(providedKey);
        canonicalKey = state.poolKeys[poolKeyHash];
        if (canonicalKey.tickSpacing == 0) {
            canonicalKey = providedKey;
            if (canonicalKey.tickSpacing == 0) revert IZoraLimitOrderBook.InvalidPoolKey();
        }

        (resolvedStart, resolvedEnd) = _resolveTickRange(ctx.poolManager, canonicalKey, isCurrency0, startTick, endTick);
        _validateTickRange(isCurrency0, resolvedStart, resolvedEnd);
    }

    function handleFillCallback(LimitOrderStorage.Layout storage state, Context memory ctx, bytes memory callbackData) internal {
        IZoraLimitOrderBook.FillCallbackData memory data = abi.decode(callbackData, (IZoraLimitOrderBook.FillCallbackData));
        executeFill(state, ctx, data);
    }

    function executeFill(LimitOrderStorage.Layout storage state, Context memory ctx, IZoraLimitOrderBook.FillCallbackData memory data) internal {
        // Bump the pool's epoch to ensure that the execution has a clean snapshot and orders created mid-fill are wait for a future price movement before being processed
        bytes32 poolKeyHash = CoinCommon.hashPoolKey(data.poolKey);
        uint256 currentEpoch = ++state.poolEpochs[poolKeyHash];

        if (data.orderIds.length == 0) {
            _fillAcrossRange(state, ctx, data);
            return;
        }

        PoolKey memory key = state.poolKeys[poolKeyHash];
        if (key.tickSpacing == 0) {
            key = data.poolKey;
            if (key.tickSpacing == 0) revert IZoraLimitOrderBook.InvalidPoolKey();
        }

        bool isCurrency0 = data.isCurrency0;
        mapping(int24 => LimitOrderTypes.Queue) storage tickQueues = state.tickQueues[poolKeyHash][LimitOrderCommon.getOrderCoin(key, isCurrency0)];
        mapping(bytes32 => LimitOrderTypes.LimitOrder) storage orders = state.limitOrders;
        address fillReferral = data.fillReferral;

        uint256 length = data.orderIds.length;
        for (uint256 i; i < length; ) {
            bytes32 orderId = data.orderIds[i];
            LimitOrderTypes.LimitOrder storage order = orders[orderId];

            if (
                order.status == LimitOrderTypes.OrderStatus.OPEN &&
                order.poolKeyHash == poolKeyHash &&
                order.isCurrency0 == isCurrency0 &&
                order.createdEpoch < currentEpoch
            ) {
                int24 orderTick = LimitOrderCommon.getOrderTick(order);
                LimitOrderTypes.Queue storage tickQueue = tickQueues[orderTick];

                _fillOrder(ctx, state, key, tickQueue, order, orderId, fillReferral);
            }

            unchecked {
                ++i;
            }
        }
    }

    function _fillAcrossRange(LimitOrderStorage.Layout storage state, Context memory ctx, IZoraLimitOrderBook.FillCallbackData memory data) private {
        if (data.maxFillCount == 0) {
            return;
        }

        bytes32 poolKeyHash = CoinCommon.hashPoolKey(data.poolKey);
        bool zeroForOne = !data.isCurrency0;
        address coin = Currency.unwrap(zeroForOne ? data.poolKey.currency1 : data.poolKey.currency0);

        mapping(int16 => uint256) storage bitmap = state.tickBitmaps[poolKeyHash][coin];
        mapping(int24 => LimitOrderTypes.Queue) storage tickQueues = state.tickQueues[poolKeyHash][coin];
        mapping(bytes32 => LimitOrderTypes.LimitOrder) storage orders = state.limitOrders;
        uint256 currentEpoch = state.poolEpochs[poolKeyHash];
        bytes32 ordersSlot;
        assembly ("memory-safe") {
            ordersSlot := orders.slot
        }

        uint256 processed;
        uint256 fillCap = data.maxFillCount;
        bool zeroDirection = zeroForOne;
        int24 cursor = data.startTick;
        int24 target = data.endTick;
        int24 tickSpacing = data.poolKey.tickSpacing;

        while (processed < fillCap) {
            if (zeroDirection ? cursor <= target : cursor >= target) break;

            (int24 nextTick, bool initialized) = TickBitmap.nextInitializedTickWithinOneWord(bitmap, cursor, tickSpacing, zeroDirection);
            bool crossesTarget = zeroDirection ? nextTick <= target : nextTick > target;
            if (crossesTarget) break;

            if (!initialized) {
                cursor = zeroDirection ? nextTick - 1 : nextTick;
                continue;
            }

            LimitOrderTypes.Queue storage tickQueue;
            bytes32 head;
            assembly ("memory-safe") {
                mstore(0x00, nextTick)
                mstore(0x20, tickQueues.slot)
                let queueSlot := keccak256(0x00, 0x40)
                tickQueue.slot := queueSlot
                head := sload(queueSlot)
            }

            if (head == bytes32(0)) {
                cursor = zeroDirection ? nextTick - 1 : nextTick;
                continue;
            }

            bytes32 orderId = head;
            while (orderId != bytes32(0) && processed < fillCap) {
                LimitOrderTypes.LimitOrder storage order;
                bytes32 nextOrderId;
                assembly ("memory-safe") {
                    mstore(0x00, orderId)
                    mstore(0x20, ordersSlot)
                    let orderSlot := keccak256(0x00, 0x40)
                    order.slot := orderSlot
                    nextOrderId := sload(orderSlot)
                }

                if (order.status != LimitOrderTypes.OrderStatus.OPEN) {
                    orderId = nextOrderId;
                    continue;
                }
                if (order.createdEpoch == currentEpoch) break;

                _fillOrder(ctx, state, data.poolKey, tickQueue, order, orderId, data.fillReferral);

                unchecked {
                    ++processed;
                }

                orderId = nextOrderId;
            }

            cursor = zeroDirection ? nextTick - 1 : nextTick;
        }
    }

    function _fillOrder(
        Context memory ctx,
        LimitOrderStorage.Layout storage state,
        PoolKey memory key,
        LimitOrderTypes.Queue storage tickQueue,
        LimitOrderTypes.LimitOrder storage order,
        bytes32 orderId,
        address fillReferral
    ) private {
        order.status = LimitOrderTypes.OrderStatus.FILLED;

        address coin = LimitOrderCommon.getOrderCoin(key, order.isCurrency0);

        (Currency coinOutCurrency, uint128 makerAmount, uint128 referralAmount) = LimitOrderLiquidity.burnAndPayout(
            ctx.poolManager,
            key,
            order,
            orderId,
            fillReferral,
            coin,
            ctx.versionLookup
        );

        int24 orderTick = LimitOrderCommon.removeOrder(state, key, coin, tickQueue, order);

        emit IZoraLimitOrderBook.LimitOrderFilled(
            order.maker,
            coin,
            Currency.unwrap(coinOutCurrency),
            order.orderSize,
            makerAmount,
            fillReferral,
            referralAmount,
            order.poolKeyHash,
            orderTick,
            orderId
        );
    }

    /**
     * @notice Derives concrete tick bounds from user input and current pool state.
     * @dev Callers may pass sentinel values (`-TICK_SENTINEL` / `TICK_SENTINEL`) to mean
     *      “start at the current tick” or “extend one spacing away”. This helper translates
     *      those sentinels into real ticks by snapping to the pool’s aligned tick grid and
     *      offsetting one spacing in the appropriate direction so fills never include
     *      orders created in the same transaction.
     *
     * @param poolManager Pool manager used to read the live tick.
     * @param key Pool whose tick spacing/current tick drive alignment.
     * @param isCurrency0 True when targeting currency0 orders (prices above anchor).
     * @param startTick User-provided start tick or sentinel.
     * @param endTick User-provided end tick or sentinel.
     * @return resolvedStart Concrete start tick after resolving sentinels.
     * @return resolvedEnd Concrete end tick after resolving sentinels.
     */
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

    /**
     * @notice Snaps the current pool tick to the nearest aligned tick and returns its neighbors.
     * @dev Uniswap v4 ticks must lie on multiples of `tickSpacing`. We round the live
     *      tick down to the nearest aligned value (handling negatives), clamp it inside
     *      the pool’s usable range, then compute the next/previous aligned ticks for
     *      callers that need to build deterministic tick windows.
     *
     * @param poolManager Pool manager used to read slot0.
     * @param key Pool key describing the pair and spacing.
     * @param spacing Tick spacing for this pool.
     * @return anchorTick Current tick rounded down to the aligned grid.
     * @return nextAligned Next aligned tick above the anchor (clamped to max usable).
     * @return prevAligned Previous aligned tick below the anchor (clamped to min usable).
     */
    function _alignedTicks(
        IPoolManager poolManager,
        PoolKey memory key,
        int24 spacing
    ) private view returns (int24 anchorTick, int24 nextAligned, int24 prevAligned) {
        int24 currentTick = _currentPoolTick(poolManager, key);
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

    function _currentPoolTick(IPoolManager poolManager, PoolKey memory key) private view returns (int24 tick) {
        (, tick, , ) = StateLibrary.getSlot0(poolManager, key.toId());
    }
}
