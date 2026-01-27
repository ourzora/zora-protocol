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
import {TransientStateLibrary} from "@uniswap/v4-core/src/libraries/TransientStateLibrary.sol";

import {IDeployedCoinVersionLookup} from "@zoralabs/coins/src/interfaces/IDeployedCoinVersionLookup.sol";
import {IZoraHookRegistry} from "@zoralabs/coins/src/interfaces/IZoraHookRegistry.sol";
import {IZoraLimitOrderBook} from "./IZoraLimitOrderBook.sol";
import {LimitOrderStorage} from "./libs/LimitOrderStorage.sol";
import {LimitOrderCreate} from "./libs/LimitOrderCreate.sol";
import {LimitOrderFill} from "./libs/LimitOrderFill.sol";
import {LimitOrderWithdraw} from "./libs/LimitOrderWithdraw.sol";
import {LimitOrderViews} from "./libs/LimitOrderViews.sol";
import {LimitOrderTypes} from "./libs/LimitOrderTypes.sol";
import {PermittedCallers} from "./access/PermittedCallers.sol";

contract ZoraLimitOrderBook is IZoraLimitOrderBook, PermittedCallers {
    IPoolManager public immutable poolManager;
    IDeployedCoinVersionLookup public immutable zoraCoinVersionLookup;
    IZoraHookRegistry public immutable zoraHookRegistry;
    address public immutable weth;

    constructor(address poolManager_, address zoraCoinVersionLookup_, address zoraHookRegistry_, address owner_, address weth_) PermittedCallers(owner_) {
        require(poolManager_ != address(0), AddressZero());
        require(zoraCoinVersionLookup_ != address(0), AddressZero());
        require(zoraHookRegistry_ != address(0), AddressZero());
        require(weth_ != address(0), AddressZero());

        poolManager = IPoolManager(poolManager_);
        zoraCoinVersionLookup = IDeployedCoinVersionLookup(zoraCoinVersionLookup_);
        zoraHookRegistry = IZoraHookRegistry(zoraHookRegistry_);
        weth = weth_;

        LimitOrderStorage.layout().maxFillCount = 50;
    }

    /// @inheritdoc IZoraLimitOrderBook
    function balanceOf(address maker, address coin) external view override returns (uint256) {
        return LimitOrderStorage.layout().makerBalances[maker][coin];
    }

    function getTickQueue(bytes32 poolKeyHash, address coin, int24 tick) internal view returns (LimitOrderTypes.Queue memory) {
        return LimitOrderStorage.layout().tickQueues[poolKeyHash][coin][tick];
    }

    function getPoolEpoch(bytes32 poolKeyHash) internal view returns (uint256) {
        return LimitOrderStorage.layout().poolEpochs[poolKeyHash];
    }

    function getMakerNonce(address maker) internal view returns (uint256) {
        return LimitOrderStorage.layout().makerNonces[maker];
    }

    /// @inheritdoc IZoraLimitOrderBook
    function create(
        PoolKey memory key,
        bool isCurrency0,
        uint256[] memory orderSizes,
        int24[] memory orderTicks,
        address maker
    ) external payable override onlyPermitted returns (bytes32[] memory) {
        return LimitOrderCreate.create(LimitOrderStorage.layout(), poolManager, key, isCurrency0, orderSizes, orderTicks, maker);
    }

    /// @inheritdoc IZoraLimitOrderBook
    function fill(PoolKey calldata key, bool isCurrency0, int24 startTick, int24 endTick, uint256 maxFillCount, address fillReferral) external override {
        uint256 defaultMaxFillCount = getMaxFillCount();
        if (maxFillCount == 0 || maxFillCount > defaultMaxFillCount) {
            maxFillCount = defaultMaxFillCount;
        }

        bool isUnlocked = TransientStateLibrary.isUnlocked(poolManager);

        // Only known Zora hooks can fill while unlocked
        if (isUnlocked) {
            require(zoraHookRegistry.isRegisteredHook(msg.sender), UnlockedFillNotAllowed());
        }

        LimitOrderStorage.Layout storage state = LimitOrderStorage.layout();
        LimitOrderFill.Context memory ctx = _fillContext();

        (PoolKey memory canonicalKey, int24 resolvedStart, int24 resolvedEnd) = LimitOrderViews.validateTickRange(
            state,
            ctx.poolManager,
            key,
            isCurrency0,
            startTick,
            endTick
        );

        IZoraLimitOrderBook.FillCallbackData memory fillData = _fillData(
            canonicalKey,
            isCurrency0,
            resolvedStart,
            resolvedEnd,
            maxFillCount,
            fillReferral,
            new bytes32[](0)
        );

        if (isUnlocked) {
            // fill while already unlocked
            LimitOrderFill.executeFill(state, ctx, fillData);
            return;
        }

        // unlock and fill
        _unlock(IZoraLimitOrderBook.CallbackId.FILL, abi.encode(fillData));
    }

    function fill(OrderBatch[] calldata batches, address fillReferral) external override {
        uint256 length = batches.length;
        for (uint256 i = 0; i < length; ++i) {
            OrderBatch calldata batch = batches[i];

            if (batch.orderIds.length != 0) {
                bytes32[] memory orderIds = batch.orderIds;
                _unlock(
                    IZoraLimitOrderBook.CallbackId.FILL,
                    abi.encode(_fillData(batch.key, batch.isCurrency0, 0, 0, orderIds.length, fillReferral, orderIds))
                );
            }
        }
    }

    /// @inheritdoc IZoraLimitOrderBook
    function withdraw(bytes32[] calldata orderIds, address coin, uint256 minAmountOut, address recipient) external override {
        _unlock(
            CallbackId.WITHDRAW_ORDERS,
            abi.encode(WithdrawOrdersCallbackData({maker: msg.sender, orderIds: orderIds, coin: coin, minAmountOut: minAmountOut, recipient: recipient}))
        );
    }

    /// @notice Processes pool-manager unlock callbacks and routes them to the correct handler.
    /// @param data ABI encoded callback identifier and callback data.
    /// @return result Optional return data for create flows.
    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(poolManager), NotPoolManager());

        (CallbackId callbackId, bytes memory callbackData) = abi.decode(data, (CallbackId, bytes));
        LimitOrderStorage.Layout storage state = LimitOrderStorage.layout();

        if (callbackId == CallbackId.CREATE) {
            return LimitOrderCreate.handleCreateCallback(state, poolManager, callbackData);
        }

        if (callbackId == CallbackId.FILL) {
            LimitOrderFill.handleFillCallback(state, _fillContext(), callbackData);
        } else if (callbackId == CallbackId.WITHDRAW_ORDERS) {
            LimitOrderWithdraw.handleWithdrawOrdersCallback(state, poolManager, weth, callbackData);
        } else {
            revert UnknownCallback();
        }

        return bytes("");
    }

    function getMaxFillCount() public view returns (uint256) {
        return LimitOrderStorage.layout().maxFillCount;
    }

    function setMaxFillCount(uint256 maxFillCount) external onlyOwner {
        LimitOrderStorage.layout().maxFillCount = maxFillCount;
    }

    receive() external payable {
        require(msg.sender == address(poolManager), NotPoolManager());
    }

    function _fillContext() private view returns (LimitOrderFill.Context memory ctx) {
        ctx.poolManager = poolManager;
        ctx.versionLookup = zoraCoinVersionLookup;
        ctx.weth = weth;
    }

    function _fillData(
        PoolKey memory key,
        bool isCurrency0,
        int24 startTick,
        int24 endTick,
        uint256 maxFillCount,
        address fillReferral,
        bytes32[] memory orderIds
    ) private pure returns (IZoraLimitOrderBook.FillCallbackData memory data) {
        data.poolKey = key;
        data.isCurrency0 = isCurrency0;
        data.startTick = startTick;
        data.endTick = endTick;
        data.maxFillCount = maxFillCount;
        data.fillReferral = fillReferral;
        data.orderIds = orderIds;
    }

    function _unlock(CallbackId callbackId, bytes memory payload) private {
        poolManager.unlock(abi.encode(callbackId, payload));
    }
}
