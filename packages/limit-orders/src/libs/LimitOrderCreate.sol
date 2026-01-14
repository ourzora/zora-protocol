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
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {LimitOrderStorage} from "./LimitOrderStorage.sol";
import {IZoraLimitOrderBook} from "../IZoraLimitOrderBook.sol";
import {LimitOrderLiquidity} from "./LimitOrderLiquidity.sol";
import {LimitOrderCommon} from "./LimitOrderCommon.sol";
import {CoinCommon} from "@zoralabs/coins/src/libs/CoinCommon.sol";
import {TransientStateLibrary} from "@uniswap/v4-core/src/libraries/TransientStateLibrary.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";

library LimitOrderCreate {
    struct CreateContext {
        bytes32 poolKeyHash;
        int24 currentTick;
        address coin;
        uint256 epoch;
        address maker;
        bool isCurrency0;
    }

    struct MintParams {
        PoolKey key;
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
        uint128 requestedSize;
        bytes32 orderId;
    }

    function create(
        LimitOrderStorage.Layout storage state,
        IPoolManager poolManager,
        PoolKey memory key,
        bool isCurrency0,
        uint256[] memory orderSizes,
        int24[] memory orderTicks,
        address maker
    ) internal returns (bytes32[] memory) {
        require(maker != address(0), IZoraLimitOrderBook.ZeroMaker());

        (IZoraLimitOrderBook.CreateCallbackData memory createData, uint256 totalSize) = _prepareCreateData(key, isCurrency0, orderSizes, orderTicks, maker);

        // Pull funds from specified address
        _pullFunds(createData.key, createData.isCurrency0, totalSize, msg.sender, address(this));

        // Check if we're already in an unlock callback to avoid double-unlock
        if (TransientStateLibrary.isUnlocked(poolManager)) {
            // Already unlocked - execute directly without calling unlock
            return _create(state, poolManager, createData);
        }

        // Not in unlock - need to unlock
        bytes memory result = poolManager.unlock(abi.encode(IZoraLimitOrderBook.CallbackId.CREATE, abi.encode(createData)));

        return abi.decode(result, (bytes32[]));
    }

    function handleCreateCallback(LimitOrderStorage.Layout storage state, IPoolManager poolManager, bytes memory payload) internal returns (bytes memory) {
        IZoraLimitOrderBook.CreateCallbackData memory data = abi.decode(payload, (IZoraLimitOrderBook.CreateCallbackData));

        bytes32[] memory orderIds = _create(state, poolManager, data);

        return abi.encode(orderIds);
    }

    function _validateOrderInputs(uint256[] memory orderSizes, int24[] memory orderTicks, address maker) private pure returns (uint256 total) {
        require(maker != address(0), IZoraLimitOrderBook.ZeroMaker());

        uint256 length = orderSizes.length;
        require(length == orderTicks.length, IZoraLimitOrderBook.ArrayLengthMismatch());

        for (uint256 i; i < length; ) {
            uint256 size = orderSizes[i];
            require(size != 0, IZoraLimitOrderBook.ZeroOrderSize());
            total += size;
            unchecked {
                ++i;
            }
        }
    }

    function _pullFunds(PoolKey memory key, bool isCurrency0, uint256 total, address payer, address book) private {
        address coin = LimitOrderCommon.getOrderCoin(key, isCurrency0);

        if (coin == address(0)) {
            require(msg.value == total, IZoraLimitOrderBook.NativeValueMismatch());
        } else {
            require(msg.value == 0, IZoraLimitOrderBook.NativeValueMismatch());

            uint256 beforeBalance = IERC20(coin).balanceOf(book);

            require(IERC20(coin).transferFrom(payer, book, total), IZoraLimitOrderBook.InsufficientTransferFunds());
            require(IERC20(coin).balanceOf(book) == beforeBalance + total, IZoraLimitOrderBook.InsufficientTransferFunds());
        }
    }

    function _create(
        LimitOrderStorage.Layout storage state,
        IPoolManager poolManager,
        IZoraLimitOrderBook.CreateCallbackData memory data
    ) private returns (bytes32[] memory orderIds) {
        PoolKey memory key = data.key;
        bytes32 poolKeyHash = CoinCommon.hashPoolKey(key);

        // If this is the first order for this pool, store the pool key
        if (state.poolKeys[poolKeyHash].tickSpacing == 0) {
            state.poolKeys[poolKeyHash] = key;
        }

        CreateContext memory ctx = CreateContext({
            poolKeyHash: poolKeyHash,
            currentTick: _getCurrentPoolTick(poolManager, key),
            coin: LimitOrderCommon.getOrderCoin(key, data.isCurrency0),
            epoch: state.poolEpochs[poolKeyHash],
            maker: data.maker,
            isCurrency0: data.isCurrency0
        });

        orderIds = new bytes32[](data.orderSizes.length);

        for (uint256 i; i < data.orderSizes.length; ) {
            orderIds[i] = _createSingleOrder(state, poolManager, key, ctx, data.orderSizes, data.orderTicks, i);
            unchecked {
                ++i;
            }
        }
    }

    function _createSingleOrder(
        LimitOrderStorage.Layout storage state,
        IPoolManager poolManager,
        PoolKey memory key,
        CreateContext memory ctx,
        uint256[] memory orderSizes,
        int24[] memory orderTicks,
        uint256 index
    ) private returns (bytes32 orderId) {
        uint256 orderSize;
        int24 orderTick;

        assembly ("memory-safe") {
            orderSize := mload(add(add(orderSizes, 0x20), mul(index, 0x20)))
            orderTick := mload(add(add(orderTicks, 0x20), mul(index, 0x20)))
        }

        (int24 tickLower, int24 tickUpper) = _calculateTickRange(ctx.isCurrency0, orderTick, key.tickSpacing);

        uint128 liquidity = LimitOrderLiquidity.liquidityForOrder(ctx.isCurrency0, orderSize, tickLower, tickUpper);
        require(liquidity != 0, IZoraLimitOrderBook.ZeroRealizedOrder());

        orderId = _generateOrderId(ctx.poolKeyHash, ctx.coin, orderTick, ctx.maker, ++state.makerNonces[ctx.maker]);

        MintParams memory mintParams = MintParams({
            key: key,
            tickLower: tickLower,
            tickUpper: tickUpper,
            liquidity: liquidity,
            requestedSize: uint128(orderSize),
            orderId: orderId
        });

        _mintAndRecordOrder(state, poolManager, orderTick, ctx, mintParams);
    }

    function _calculateTickRange(bool isCurrency0, int24 orderTick, int24 spacing) private pure returns (int24 tickLower, int24 tickUpper) {
        if (isCurrency0) {
            tickLower = orderTick;
            tickUpper = orderTick + spacing;
        } else {
            tickLower = orderTick - spacing;
            tickUpper = orderTick;
        }
    }

    function _generateOrderId(bytes32 poolKeyHash, address coin, int24 orderTick, address maker, uint256 nonce) private pure returns (bytes32 orderId) {
        assembly ("memory-safe") {
            let ptr := mload(0x40)
            mstore(ptr, poolKeyHash)
            mstore(add(ptr, 0x20), coin)
            mstore(add(ptr, 0x40), orderTick)
            mstore(add(ptr, 0x60), maker)
            mstore(add(ptr, 0x80), nonce)
            orderId := keccak256(ptr, 0xa0)
        }
    }

    function _mintAndRecordOrder(
        LimitOrderStorage.Layout storage state,
        IPoolManager poolManager,
        int24 orderTick,
        CreateContext memory ctx,
        MintParams memory mintParams
    ) private {
        (uint128 realized, uint128 refunded) = _mintLiquidity(poolManager, ctx.isCurrency0, mintParams);

        if (refunded != 0) {
            LimitOrderLiquidity.refundResidual(mintParams.key, ctx.isCurrency0, ctx.maker, refunded);
        }

        LimitOrderCommon.recordCreation(state, ctx, mintParams, orderTick, realized);
    }

    function _mintLiquidity(IPoolManager poolManager, bool isCurrency0, MintParams memory params) private returns (uint128 realizedSize, uint128 refunded) {
        (BalanceDelta delta, ) = poolManager.modifyLiquidity(
            params.key,
            ModifyLiquidityParams({
                tickLower: params.tickLower,
                tickUpper: params.tickUpper,
                liquidityDelta: int256(uint256(params.liquidity)),
                salt: params.orderId
            }),
            ""
        );

        int128 amount0 = delta.amount0();
        int128 amount1 = delta.amount1();

        if (isCurrency0) {
            realizedSize = amount0 < 0 ? uint128(uint256(int256(-amount0))) : 0;
        } else {
            realizedSize = amount1 < 0 ? uint128(uint256(int256(-amount1))) : 0;
        }

        require(realizedSize != 0, IZoraLimitOrderBook.ZeroRealizedOrder());

        if (realizedSize < params.requestedSize) {
            refunded = params.requestedSize - realizedSize;
        }

        LimitOrderLiquidity.settleAfterCreate(poolManager, params.key, isCurrency0);
    }

    function _prepareCreateData(
        PoolKey memory key,
        bool isCurrency0,
        uint256[] memory orderSizes,
        int24[] memory orderTicks,
        address maker
    ) private pure returns (IZoraLimitOrderBook.CreateCallbackData memory data, uint256 totalSize) {
        totalSize = _validateOrderInputs(orderSizes, orderTicks, maker);
        data = IZoraLimitOrderBook.CreateCallbackData({key: key, isCurrency0: isCurrency0, orderSizes: orderSizes, orderTicks: orderTicks, maker: maker});
    }

    function _getCurrentPoolTick(IPoolManager poolManager, PoolKey memory key) private view returns (int24 tick) {
        (, tick, , ) = StateLibrary.getSlot0(poolManager, PoolIdLibrary.toId(key));
    }
}
