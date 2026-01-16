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

    struct Context {
        IPoolManager poolManager;
        IDeployedCoinVersionLookup versionLookup;
        address weth;
    }

    function handleFillCallback(LimitOrderStorage.Layout storage state, Context memory ctx, bytes memory callbackData) internal {
        IZoraLimitOrderBook.FillCallbackData memory data = abi.decode(callbackData, (IZoraLimitOrderBook.FillCallbackData));
        executeFill(state, ctx, data);
    }

    function executeFill(LimitOrderStorage.Layout storage state, Context memory ctx, IZoraLimitOrderBook.FillCallbackData memory data) internal {
        // Bump the pool's epoch to ensure that the execution has a clean snapshot and orders created mid-fill are wait for a future price movement before being processed
        bytes32 poolKeyHash = CoinCommon.hashPoolKey(data.poolKey);
        uint256 currentEpoch = ++state.poolEpochs[poolKeyHash];

        PoolKey memory key = state.poolKeys[poolKeyHash];
        if (key.tickSpacing == 0) {
            key = data.poolKey;
            if (key.tickSpacing == 0) revert IZoraLimitOrderBook.InvalidPoolKey();
        }

        if (data.orderIds.length == 0) {
            _fillAcrossRange(state, ctx, data);
            return;
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
                if (!_hasCrossed(order, _currentPoolTick(ctx.poolManager, key))) {
                    continue;
                }

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
            if (zeroDirection ? cursor <= target : cursor >= target) {
                break;
            }

            (int24 nextTick, bool initialized) = TickBitmap.nextInitializedTickWithinOneWord(bitmap, cursor, tickSpacing, zeroDirection);
            bool crossesTarget = zeroDirection ? nextTick <= target : nextTick > target;
            if (crossesTarget) {
                break;
            }

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
                if (order.createdEpoch == currentEpoch) {
                    break;
                }
                if (!_hasCrossed(order, _currentPoolTick(ctx.poolManager, data.poolKey))) {
                    return;
                }

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

        // Get both input and output currencies
        address coinIn = LimitOrderCommon.getOrderCoin(key, order.isCurrency0);
        address coinOut = LimitOrderCommon.getOrderCoin(key, !order.isCurrency0);

        // Pass output currency to burnAndPayout (not input currency)
        // This ensures payout uses the OUTPUT coin's configured payout path
        (Currency coinOutCurrency, uint128 makerAmount, uint128 referralAmount) = LimitOrderLiquidity.burnAndPayout(
            ctx.poolManager,
            key,
            order,
            orderId,
            fillReferral,
            coinOut,
            ctx.versionLookup,
            ctx.weth
        );

        // Use input currency for removing from order book
        int24 orderTick = LimitOrderCommon.removeOrder(state, key, coinIn, tickQueue, order);

        emit IZoraLimitOrderBook.LimitOrderFilled(
            order.maker,
            coinIn,
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

    function _currentPoolTick(IPoolManager poolManager, PoolKey memory key) private view returns (int24 tick) {
        (, tick, , ) = StateLibrary.getSlot0(poolManager, key.toId());
    }

    /// @dev Returns true if the pool tick has fully crossed the order's range.
    function _hasCrossed(LimitOrderTypes.LimitOrder storage order, int24 currentTick) private view returns (bool) {
        return order.isCurrency0 ? currentTick >= order.tickUpper : currentTick <= order.tickLower;
    }
}
