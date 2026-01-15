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

import {LimitOrderStorage} from "./LimitOrderStorage.sol";
import {IZoraLimitOrderBook} from "../IZoraLimitOrderBook.sol";
import {LimitOrderTypes} from "./LimitOrderTypes.sol";
import {LimitOrderCommon} from "./LimitOrderCommon.sol";
import {LimitOrderLiquidity} from "./LimitOrderLiquidity.sol";

library LimitOrderWithdraw {
    function handleWithdrawOrdersCallback(LimitOrderStorage.Layout storage state, IPoolManager poolManager, address weth, bytes memory payload) internal {
        IZoraLimitOrderBook.WithdrawOrdersCallbackData memory data = abi.decode(payload, (IZoraLimitOrderBook.WithdrawOrdersCallbackData));

        withdrawOrders(state, poolManager, weth, data.maker, data.orderIds, data.coin, data.minAmountOut, data.recipient);
    }

    function withdrawOrders(
        LimitOrderStorage.Layout storage state,
        IPoolManager poolManager,
        address weth,
        address maker,
        bytes32[] memory orderIds,
        address coin,
        uint256 minAmountOut,
        address recipient
    ) internal {
        require(recipient != address(0), IZoraLimitOrderBook.AddressZero());
        uint256 orderCount = orderIds.length;
        require(orderCount != 0, IZoraLimitOrderBook.InvalidOrder());

        uint256 totalWithdrawn;

        for (uint256 i; i < orderCount; ++i) {
            bytes32 orderId = orderIds[i];
            LimitOrderTypes.LimitOrder storage order = state.limitOrders[orderId];

            require(order.maker != address(0), IZoraLimitOrderBook.InvalidOrder());
            require(order.maker == maker, IZoraLimitOrderBook.OrderNotMaker());
            require(order.status == LimitOrderTypes.OrderStatus.OPEN, IZoraLimitOrderBook.OrderClosed());

            uint128 orderSize = order.orderSize; // Cache before cancellation
            address currentCoin = _cancelOrder(state, poolManager, weth, maker, orderId, order, recipient);

            // Validate order coin matches expected coin
            if (currentCoin != coin) {
                revert IZoraLimitOrderBook.CoinMismatch(orderId, coin, currentCoin);
            }

            totalWithdrawn += orderSize;

            // Early termination if threshold reached
            if (minAmountOut > 0 && totalWithdrawn >= minAmountOut) {
                break;
            }
        }

        // Revert if threshold not reached
        require(totalWithdrawn >= minAmountOut, IZoraLimitOrderBook.MinAmountNotReached(totalWithdrawn, minAmountOut));
    }

    function _cancelOrder(
        LimitOrderStorage.Layout storage state,
        IPoolManager poolManager,
        address weth,
        address maker,
        bytes32 orderId,
        LimitOrderTypes.LimitOrder storage order,
        address recipient
    ) private returns (address coin) {
        PoolKey memory key = state.poolKeys[order.poolKeyHash];
        require(key.tickSpacing != 0, IZoraLimitOrderBook.InvalidOrder());

        // Prevent withdrawal of fillable orders - they must be filled instead
        (, int24 currentTick, , ) = StateLibrary.getSlot0(poolManager, PoolIdLibrary.toId(key));
        bool fillable = order.isCurrency0 ? currentTick >= order.tickUpper : currentTick <= order.tickLower;
        require(!fillable, IZoraLimitOrderBook.OrderFillable());

        int24 orderTick = LimitOrderCommon.getOrderTick(order);
        coin = LimitOrderCommon.getOrderCoin(key, order.isCurrency0);

        LimitOrderTypes.Queue storage tickQueue = state.tickQueues[order.poolKeyHash][coin][orderTick];

        // Cache values needed after state changes
        int24 tickLower = order.tickLower;
        int24 tickUpper = order.tickUpper;
        uint128 liquidity = order.liquidity;
        bool isCurrency0 = order.isCurrency0;

        // Effects before interactions (CEI pattern)
        order.status = LimitOrderTypes.OrderStatus.INACTIVE;
        LimitOrderCommon.removeOrder(state, key, coin, tickQueue, order);

        // External call after state is updated
        LimitOrderLiquidity.burnAndRefund(poolManager, key, tickLower, tickUpper, liquidity, orderId, recipient, isCurrency0, weth);

        emit IZoraLimitOrderBook.LimitOrderUpdated(maker, coin, order.poolKeyHash, isCurrency0, orderTick, 0, orderId, true);
    }
}
