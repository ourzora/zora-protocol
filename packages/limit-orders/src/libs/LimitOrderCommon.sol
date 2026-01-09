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

library LimitOrderCommon {
    /// @dev Currency0 orders are executed when the price rises to the lower tick.
    ///      Currency1 orders are executed when the price falls to the upper tick.
    function getOrderTick(LimitOrderTypes.LimitOrder storage order) internal view returns (int24) {
        return order.isCurrency0 ? order.tickLower : order.tickUpper;
    }

    function getOrderCoin(PoolKey memory key, bool isCurrency0) internal pure returns (address) {
        return Currency.unwrap(isCurrency0 ? key.currency0 : key.currency1);
    }

    function recordCreation(
        LimitOrderStorage.Layout storage state,
        PoolKey memory key,
        bytes32 poolKeyHash,
        bytes32 orderId,
        address maker,
        address coin,
        bool isCurrency0,
        int24 orderTick,
        int24 currentTick,
        uint256 epoch,
        uint128 liquidity,
        uint128 realizedSize,
        int24 tickLower,
        int24 tickUpper
    ) internal {
        LimitOrderTypes.LimitOrder storage order = state.limitOrders[orderId];
        order.orderSize = realizedSize;
        order.liquidity = liquidity;
        order.tickLower = tickLower;
        order.tickUpper = tickUpper;
        order.createdEpoch = uint32(epoch);
        order.status = LimitOrderTypes.OrderStatus.OPEN;
        order.isCurrency0 = isCurrency0;
        order.maker = maker;
        order.poolKeyHash = poolKeyHash;

        LimitOrderTypes.Queue storage tickQueue = state.tickQueues[poolKeyHash][coin][orderTick];
        tickQueue.balance += realizedSize;

        LimitOrderBitmap.setIfFirst(state.tickBitmaps[poolKeyHash][coin], orderTick, key.tickSpacing, tickQueue.length);
        LimitOrderQueues.enqueue(tickQueue, state.limitOrders, orderId);

        uint256 newMakerBalance = state.makerBalances[maker][coin] + realizedSize;
        state.makerBalances[maker][coin] = newMakerBalance;

        emit IZoraLimitOrderBook.LimitOrderCreated(maker, coin, poolKeyHash, isCurrency0, orderTick, currentTick, realizedSize, orderId);
        emit IZoraLimitOrderBook.MakerBalanceUpdated(maker, coin, newMakerBalance);
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
