// SPDX-License-Identifier: ZORA-DELAYED-OSL-v1
// This software is licensed under the Zora Delayed Open Source License.
// Under this license, you may use, copy, modify, and distribute this software for
// non-commercial purposes only. Commercial use and competitive products are prohibited
// until the "Open Date" (3 years from first public distribution or earlier at Zora's discretion),
// at which point this software automatically becomes available under the MIT License.
// Full license terms available at: https://docs.zora.co/coins/license
pragma solidity ^0.8.28;

import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

import {IZoraLimitOrderBook} from "../IZoraLimitOrderBook.sol";
import {LimitOrderStorage} from "./LimitOrderStorage.sol";
import {LimitOrderTypes} from "./LimitOrderTypes.sol";
import {LimitOrderQueues} from "./LimitOrderQueues.sol";
import {LimitOrderBitmap} from "./LimitOrderBitmap.sol";
import {LimitOrderCreate} from "./LimitOrderCreate.sol";

library LimitOrderCommon {
    /// @dev Currency0 orders are executed when the price rises to the upper tick.
    ///      Currency1 orders are executed when the price falls to the lower tick.
    function getOrderTick(LimitOrderTypes.LimitOrder storage order) internal view returns (int24) {
        return order.isCurrency0 ? order.tickUpper : order.tickLower;
    }

    function getOrderCoin(PoolKey memory key, bool isCurrency0) internal pure returns (address) {
        return Currency.unwrap(isCurrency0 ? key.currency0 : key.currency1);
    }

    function recordCreation(
        LimitOrderStorage.Layout storage state,
        LimitOrderCreate.CreateContext memory ctx,
        LimitOrderCreate.MintParams memory mintParams,
        int24 orderTick,
        uint128 realizedSize
    ) internal {
        _initializeOrder(state.limitOrders[mintParams.orderId], ctx, mintParams, realizedSize);
        _addToQueue(state, ctx, mintParams, orderTick, realizedSize);
        _updateMakerBalanceAndEmit(state, ctx, mintParams.orderId, orderTick, realizedSize);
    }

    function _initializeOrder(
        LimitOrderTypes.LimitOrder storage order,
        LimitOrderCreate.CreateContext memory ctx,
        LimitOrderCreate.MintParams memory mintParams,
        uint128 realizedSize
    ) private {
        order.orderSize = realizedSize;
        order.liquidity = mintParams.liquidity;
        order.tickLower = mintParams.tickLower;
        order.tickUpper = mintParams.tickUpper;
        order.createdEpoch = uint32(ctx.epoch);
        order.status = LimitOrderTypes.OrderStatus.OPEN;
        order.isCurrency0 = ctx.isCurrency0;
        order.maker = ctx.maker;
        order.poolKeyHash = ctx.poolKeyHash;
    }

    function _addToQueue(
        LimitOrderStorage.Layout storage state,
        LimitOrderCreate.CreateContext memory ctx,
        LimitOrderCreate.MintParams memory mintParams,
        int24 orderTick,
        uint128 realizedSize
    ) private {
        LimitOrderTypes.Queue storage tickQueue = state.tickQueues[ctx.poolKeyHash][ctx.coin][orderTick];
        tickQueue.balance += realizedSize;

        LimitOrderBitmap.setIfFirst(state.tickBitmaps[ctx.poolKeyHash][ctx.coin], orderTick, mintParams.key.tickSpacing, tickQueue.length);
        LimitOrderQueues.enqueue(tickQueue, state.limitOrders, mintParams.orderId);
    }

    function _updateMakerBalanceAndEmit(
        LimitOrderStorage.Layout storage state,
        LimitOrderCreate.CreateContext memory ctx,
        bytes32 orderId,
        int24 orderTick,
        uint128 realizedSize
    ) private {
        uint256 newMakerBalance = state.makerBalances[ctx.maker][ctx.coin] + realizedSize;
        state.makerBalances[ctx.maker][ctx.coin] = newMakerBalance;

        emit IZoraLimitOrderBook.LimitOrderCreated(ctx.maker, ctx.coin, ctx.poolKeyHash, ctx.isCurrency0, orderTick, ctx.currentTick, realizedSize, orderId);
        emit IZoraLimitOrderBook.MakerBalanceUpdated(ctx.maker, ctx.coin, newMakerBalance);
    }

    function removeOrder(
        LimitOrderStorage.Layout storage state,
        PoolKey memory key,
        address coin,
        LimitOrderTypes.Queue storage tickQueue,
        LimitOrderTypes.LimitOrder storage order
    ) internal returns (int24 orderTick) {
        uint128 size = order.orderSize;
        tickQueue.balance -= size;

        LimitOrderQueues.unlink(tickQueue, state.limitOrders, order);
        LimitOrderQueues.clearLinks(order);

        orderTick = getOrderTick(order);
        LimitOrderBitmap.clearIfEmpty(state.tickBitmaps[order.poolKeyHash][coin], orderTick, key.tickSpacing, tickQueue.length);

        address maker = order.maker;
        uint256 newMakerBalance = state.makerBalances[maker][coin] - size;
        state.makerBalances[maker][coin] = newMakerBalance;
        emit IZoraLimitOrderBook.MakerBalanceUpdated(maker, coin, newMakerBalance);
    }
}
