// SPDX-License-Identifier: ZORA-DELAYED-OSL-v1
// This software is licensed under the Zora Delayed Open Source License.
// Under this license, you may use, copy, modify, and distribute this software for
// non-commercial purposes only. Commercial use and competitive products are prohibited
// until the "Open Date" (3 years from first public distribution or earlier at Zora's discretion),
// at which point this software automatically becomes available under the MIT License.
// Full license terms available at: https://docs.zora.co/coins/license
pragma solidity ^0.8.23;

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IZoraLimitOrderBookCoinsInterface} from "@zoralabs/coins/src/interfaces/IZoraLimitOrderBookCoinsInterface.sol";

interface IZoraLimitOrderBook is IZoraLimitOrderBookCoinsInterface {
    struct OrderBatch {
        PoolKey key;
        bool isCurrency0;
        bytes32[] orderIds;
    }

    /// @dev Callback ids for the V4 pool manager
    enum CallbackId {
        CREATE,
        FILL,
        WITHDRAW_ORDERS
    }

    /// @dev Data echoed back to hooks when create flows resolve
    struct CreateCallbackData {
        PoolKey key;
        bool isCurrency0;
        uint256[] orderSizes;
        int24[] orderTicks;
        address maker;
    }

    /// @dev Data forwarded when the pool manager triggers a fill.
    struct FillCallbackData {
        PoolKey poolKey;
        bool isCurrency0;
        int24 startTick;
        int24 endTick;
        uint256 maxFillCount;
        address fillReferral;
        bytes32[] orderIds;
    }

    /// @dev Data used to withdraw from a maker's individual orders
    struct WithdrawOrdersCallbackData {
        address maker;
        bytes32[] orderIds;
        address coin;
        uint256 minAmountOut;
        address recipient;
    }

    /// @notice Emitted when a new order joins a tick queue.
    event LimitOrderCreated(
        address indexed maker,
        address indexed coin,
        bytes32 poolKeyHash,
        bool isCurrency0,
        int24 orderTick, // The tick at which the limit order is placed
        int24 currentTick, // The current tick of the pool when the order was created
        uint128 orderSize,
        bytes32 orderId
    );

    /// @notice Emitted when an order is amended or marked inactive.
    event LimitOrderUpdated(
        address indexed maker,
        address indexed coin,
        bytes32 poolKeyHash,
        bool isCurrency0,
        int24 tick,
        uint128 orderSize,
        bytes32 orderId,
        bool isCancelled
    );

    /// @notice Emitted when an order is filled and removed from the book.
    event LimitOrderFilled(
        address indexed maker,
        address indexed coinIn,
        address coinOut,
        uint128 amountIn,
        uint128 amountOut,
        address fillReferral,
        uint128 fillReferralAmount,
        bytes32 poolKeyHash,
        int24 tick,
        bytes32 orderId
    );

    /// @notice Emitted when a maker's aggregate balance for a coin changes.
    event MakerBalanceUpdated(address indexed maker, address indexed coin, uint256 newBalance);

    /// @notice Caller must be a registered Zora hook.
    error OnlyZoraHook();
    /// @notice Caller must be the configured pool manager.
    error NotPoolManager();
    /// @notice Input arrays must have equal length.
    error ArrayLengthMismatch();
    /// @notice Orders must specify a non-zero size.
    error ZeroOrderSize();
    /// @notice Maker address cannot be zero.
    error ZeroMaker();
    /// @notice Supplied ETH must match expected amount.
    error NativeValueMismatch();
    /// @notice Forwarded funds from hook were insufficient.
    error InsufficientForwardedFunds();
    /// @notice Transfer in of funds failed or was insufficient.
    error InsufficientTransferFunds();
    /// @notice Fill requests must cap the number of orders processed.
    error MaxFillCountCannotBeZero();
    /// @notice Referenced pool key hash is unknown.
    error InvalidPoolKey();
    /// @notice Tick range inputs were invalid or misaligned.
    error InvalidFillWindow(int24 startTick, int24 endTick, bool isCurrency0);
    /// @notice Address argument was zero.
    error AddressZero();
    /// @notice Order id was not found.
    error InvalidOrder();
    /// @notice Operation attempted by non-maker.
    error OrderNotMaker();
    /// @notice Order is no longer open.
    error OrderClosed();
    /// @notice Callback realized zero fills when one was expected.
    error ZeroRealizedOrder();
    /// @notice Unlock callback id was not recognized.
    error UnknownCallback();
    /// @notice Router caller failed to expose the original message sender.
    error RouterMsgSenderInvalid();
    /// @notice Non-hook caller attempted to fill orders while pool is unlocked.
    error UnlockedFillNotAllowed();
    /// @notice Withdrawal did not reach minimum amount threshold.
    error MinAmountNotReached(uint256 withdrawn, uint256 minAmountOut);
    /// @notice Order coin does not match expected coin for batch withdrawal.
    error CoinMismatch(bytes32 orderId, address expectedCoin, address actualCoin);

    /// @notice Creates limit orders, pulling funds from msg.sender when pool manager is locked, or using funds already in manager when unlocked.
    /// @dev This function is access-controlled via OpenZeppelin's AccessManager. The caller must have the appropriate role
    ///      as configured in the AccessManager contract. Initially, this can be set to PUBLIC_ROLE to allow anyone to create orders,
    ///      or it can be restricted to specific addresses/roles for permissioned operation.
    /// @param key Pool key specifying currency pair and tick spacing.
    /// @param isCurrency0 Whether the orders are denominated in currency0.
    /// @param orderSizes Order liquidity sizes.
    /// @param orderTicks Corresponding ticks.
    /// @param maker Address of the maker who will own the orders.
    /// @return orderIds Deterministic order identifiers.
    function create(
        PoolKey memory key,
        bool isCurrency0,
        uint256[] memory orderSizes,
        int24[] memory orderTicks,
        address maker
    ) external payable returns (bytes32[] memory orderIds);

    /// @notice Fills limit orders within a tick window.
    /// @param key Pool key whose orders should be processed.
    /// @param isCurrency0 Whether currency0 orders are targeted; otherwise currency1.
    /// @param startTick Inclusive starting tick. Use `-type(int24).max` for the default lower bound.
    /// @param endTick Inclusive ending tick. Use `type(int24).max` for the default upper bound.
    /// @param maxFillCount Maximum orders to fill in this pass.
    /// @param fillReferral Address to receive accrued LP fees; use address(0) to give fees to maker.
    function fill(PoolKey calldata key, bool isCurrency0, int24 startTick, int24 endTick, uint256 maxFillCount, address fillReferral) external;

    /// @notice Fills explicit order ids grouped by pool.
    /// @param batches Array of per-pool batches containing order ids to process.
    /// @param fillReferral Address to receive accrued LP fees; use address(0) to give fees to maker.
    function fill(OrderBatch[] calldata batches, address fillReferral) external;

    /// @notice Cancels orders and withdraws resulting funds to a recipient.
    /// @dev Orders are cancelled sequentially until minAmountOut is reached.
    ///      If minAmountOut is 0, all provided orders are cancelled.
    ///      Reverts if total withdrawn is less than minAmountOut.
    /// @param orderIds Order identifiers to cancel.
    /// @param coin The coin address that all orders must match (use address(0) for native ETH).
    /// @param minAmountOut Minimum amount to withdraw (0 = cancel all provided orders).
    /// @param recipient Destination for returned assets.
    function withdraw(bytes32[] calldata orderIds, address coin, uint256 minAmountOut, address recipient) external;

    /// @notice Returns the aggregate balance of open orders for a maker/coin pair.
    /// @param maker Address of the maker.
    /// @param coin Address of the coin (use address(0) for native ETH).
    /// @return balance Total value of open orders.
    function balanceOf(address maker, address coin) external view returns (uint256 balance);

    function getMaxFillCount() external view returns (uint256);

    /// @notice Sets the maximum number of orders that can be filled in a single fill operation.
    /// @dev This function is access-controlled via OpenZeppelin's AccessManager. The caller must have the appropriate role
    ///      as configured in the AccessManager contract.
    /// @param maxFillCount The new maximum fill count value.
    function setMaxFillCount(uint256 maxFillCount) external;
}
