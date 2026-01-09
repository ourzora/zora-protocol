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
import {BalanceDelta, BalanceDeltaLibrary} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IZoraLimitOrderBook} from "../IZoraLimitOrderBook.sol";
import {SwapLimitOrders, LimitOrderConfig, Orders} from "../libs/SwapLimitOrders.sol";
import {ISwapRouter} from "@zoralabs/shared-contracts/interfaces/uniswap/ISwapRouter.sol";
import {ISupportsLimitOrderFill} from "@zoralabs/coins/src/interfaces/ISupportsLimitOrderFill.sol";
import {IMsgSender} from "@zoralabs/coins/src/interfaces/IMsgSender.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {TransientSlot} from "@openzeppelin/contracts/utils/TransientSlot.sol";
import {Path} from "@zoralabs/shared-contracts/libs/UniswapV3/Path.sol";
import {V3ToV4SwapLib} from "@zoralabs/coins/src/libs/V3ToV4SwapLib.sol";
import {SimpleAccessManaged} from "../access/SimpleAccessManaged.sol";
import {Permit2Payments} from "../libs/Permit2Payments.sol";

/// @title SwapWithLimitOrders
/// @notice Standalone router contract that executes swaps with automatic limit order placement and filling.
/// @dev This contract uses the poolManager unlock/callback pattern to execute swaps, place limit orders
///      based on the tick range crossed during the swap, and attempt to fill those orders in a single transaction.
///      Users call swapWithLimitOrders() directly, which triggers the unlock callback flow.
///      Uses Permit2 for token approvals, matching the universal-router pattern.
/// @author oveddan
contract SwapWithLimitOrders is IMsgSender, Permit2Payments {
    using SafeERC20 for IERC20;
    using BalanceDeltaLibrary for BalanceDelta;
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolKey;
    using Path for bytes;

    /// @notice The Uniswap V4 pool manager
    IPoolManager public immutable poolManager;

    /// @notice The limit order book contract
    IZoraLimitOrderBook public immutable zoraLimitOrderBook;

    /// @notice The Uniswap V3 swap router
    ISwapRouter public immutable swapRouter;

    /// @notice Canonical limit order configuration
    LimitOrderConfig private _limitOrderConfig;

    /// @notice Transient storage slot for tracking the current maker during swap execution
    bytes32 private constant _MAKER_SLOT = keccak256("SwapWithLimitOrders.maker");

    /// @notice Parameters for executing a swap with limit order placement
    struct SwapWithLimitOrdersParams {
        address recipient; // Who receives the swap output
        LimitOrderConfig limitOrderConfig; // Limit order configuration
        address inputCurrency; // Currency to use for swap (address(0) for ETH)
        uint256 inputAmount; // Amount of input currency
        bytes v3Route; // V3 route from input → backing currency (empty if not needed)
        PoolKey[] v4Route; // V4 route including target pool as last element
        uint256 minAmountOut; // Minimum amount of coins to receive from final swap
    }

    /// @notice Internal callback data passed to unlockCallback
    struct CallbackData {
        address recipient;
        PoolKey[] v4Route; // Target pool is last element
        uint256 currencyAmount; // Amount after V3 swap
        address currencyReceived; // Currency received from V3 swap
        uint256 minAmountOut;
        LimitOrderConfig limitOrderConfig; // Limit order configuration for order creation
    }

    /// @notice Data returned from unlockCallback
    struct UnlockResult {
        uint256 coinAmount; // Amount of coins received
        address coinAddress; // Address of the coin
        bool isCoinCurrency0; // Whether coin is currency0 in target pool
        int24 currentTick; // Tick after swaps
        uint160 sqrtPriceX96; // Price after swaps
    }

    /// @notice Represents a limit order created with its configuration
    struct CreatedOrder {
        bytes32 orderId; // The order ID
        uint256 multiple; // The price multiple used (e.g., 2e18 for 2x)
        uint256 percentage; // The percentage of swap output allocated (basis points)
    }

    /// @notice Emitted when a swap with limit order placement is executed
    /// @param orders Array of created orders with their configuration. Only includes orders
    ///               that were actually created (skipped rungs due to rounding are omitted).
    event SwapWithLimitOrdersExecuted(
        address indexed sender,
        address indexed recipient,
        PoolKey poolKey,
        BalanceDelta delta,
        int24 tickBeforeSwap,
        int24 tickAfterSwap,
        CreatedOrder[] orders
    );

    /// @notice Emitted when limit order config is updated
    event LimitOrderConfigUpdated(uint256[] multiples, uint256[] percentages);

    /// @notice Error thrown when caller is not the pool manager
    error OnlyPoolManager();

    /// @notice Error thrown when caller is not the authority
    error OnlyAuthority();

    /// @notice Error thrown when config does not match canonical config
    error InvalidLimitOrderConfig();

    /// @notice Error thrown when swap delta is zero
    error ZeroSwapDelta();

    /// @notice Error thrown when final swap output is below minimum
    error InsufficientOutputAmount();

    /// @notice Error thrown when v4Route is empty
    error EmptyV4Route();

    /// @notice Constructor
    /// @param poolManager_ The Uniswap V4 pool manager
    /// @param zoraLimitOrderBook_ The limit order book contract
    /// @param swapRouter_ The Uniswap V3 swap router
    /// @param permit2_ The Permit2 contract address (0x000000000022D473030F116dDEE9F6B43aC78BA3)
    constructor(IPoolManager poolManager_, IZoraLimitOrderBook zoraLimitOrderBook_, ISwapRouter swapRouter_, address permit2_) Permit2Payments(permit2_) {
        require(address(poolManager_) != address(0), "PoolManager cannot be zero");
        require(address(zoraLimitOrderBook_) != address(0), "ZoraLimitOrderBook cannot be zero");
        require(address(swapRouter_) != address(0), "SwapRouter cannot be zero");
        require(permit2_ != address(0), "Permit2 cannot be zero");
        poolManager = poolManager_;
        zoraLimitOrderBook = zoraLimitOrderBook_;
        swapRouter = swapRouter_;
    }

    /// @inheritdoc IMsgSender
    function msgSender() external view returns (address) {
        TransientSlot.AddressSlot slot = TransientSlot.asAddress(_MAKER_SLOT);
        return TransientSlot.tload(slot);
    }

    /// @notice Sets the canonical limit order configuration
    /// @dev Only callable by zoraLimitOrderBook.authority()
    /// @param config The new limit order configuration
    function setLimitOrderConfig(LimitOrderConfig memory config) external {
        require(msg.sender == SimpleAccessManaged(address(zoraLimitOrderBook)).authority(), OnlyAuthority());
        SwapLimitOrders.validate(config);
        _limitOrderConfig = config;
        emit LimitOrderConfigUpdated(config.multiples, config.percentages);
    }

    /// @notice Returns the current limit order configuration
    /// @return The current limit order configuration
    function getLimitOrderConfig() external view returns (LimitOrderConfig memory) {
        return _limitOrderConfig;
    }

    /// @notice Executes a swap with automatic limit order placement and filling
    /// @param params The swap and limit order parameters
    /// @return delta The balance delta from the swap
    function swapWithLimitOrders(SwapWithLimitOrdersParams calldata params) external payable returns (BalanceDelta delta) {
        // Store recipient (maker) in transient storage for IMsgSender interface
        TransientSlot.AddressSlot slot = TransientSlot.asAddress(_MAKER_SLOT);
        TransientSlot.tstore(slot, params.recipient);

        // Validate limit order parameters (signature, percentages, multiples, etc.)
        SwapLimitOrders.validate(params.limitOrderConfig);

        // Validate config matches canonical config
        _validateConfigMatchesCurrent(params.limitOrderConfig);

        // Require v4Route has at least one pool (the target)
        require(params.v4Route.length > 0, EmptyV4Route());

        // Validate routes
        V3ToV4SwapLib.validateRoutes(params.v3Route, params.inputCurrency, params.v4Route);

        // Validate and transfer input currency from msg.sender using Permit2
        V3ToV4SwapLib.permit2TransferFrom(PERMIT2, params.inputCurrency, params.inputAmount, msg.sender, address(this), msg.value);

        // Get target pool (last element in v4Route)
        PoolKey memory targetPool = params.v4Route[params.v4Route.length - 1];

        // Get tick before swap
        (, int24 tickBeforeSwap, , ) = StateLibrary.getSlot0(poolManager, targetPool.toId());

        // Execute V3 swap (inputCurrency -> backing currency)
        (uint256 currencyAmount, address currencyReceived) = V3ToV4SwapLib.executeV3Swap(
            swapRouter,
            V3ToV4SwapLib.V3SwapParams({
                v3Route: params.v3Route,
                inputCurrency: params.inputCurrency,
                inputAmount: params.inputAmount,
                recipient: address(this)
            })
        );

        // Prepare callback data for V4 swaps + limit order creation
        CallbackData memory callbackData = CallbackData({
            recipient: params.recipient,
            v4Route: params.v4Route,
            currencyAmount: currencyAmount,
            currencyReceived: currencyReceived,
            minAmountOut: params.minAmountOut,
            limitOrderConfig: params.limitOrderConfig
        });

        // Execute V4 swaps + create orders via unlock callback
        bytes memory result = poolManager.unlock(abi.encode(callbackData));

        (CreatedOrder[] memory orders, bool isCoinCurrency0, int24 tickAfterSwap) = abi.decode(result, (CreatedOrder[], bool, int24));

        // Check if hook supports limit order filling using ERC165
        bool hookSupportsFill = IERC165(address(targetPool.hooks)).supportsInterface(type(ISupportsLimitOrderFill).interfaceId);

        // Router-based filling for legacy hooks
        if (!hookSupportsFill && orders.length > 0 && tickBeforeSwap != tickAfterSwap) {
            _fillOrders(targetPool, !isCoinCurrency0, tickBeforeSwap, tickAfterSwap);
        }

        emit SwapWithLimitOrdersExecuted(msg.sender, params.recipient, targetPool, BalanceDelta.wrap(0), tickBeforeSwap, tickAfterSwap, orders);

        // Clear maker from transient storage
        TransientSlot.tstore(slot, address(0));

        return BalanceDelta.wrap(0);
    }

    /// @notice Callback function called by the pool manager during unlock
    /// @dev This function executes V4 swaps and settles coins to recipient
    /// @param data Encoded CallbackData
    /// @return Encoded UnlockResult containing coin amount and pool info
    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        if (msg.sender != address(poolManager)) {
            revert OnlyPoolManager();
        }

        CallbackData memory callbackData = abi.decode(data, (CallbackData));

        // Execute V4 multi-hop swap
        V3ToV4SwapLib.V4SwapResult memory swapResult = _executeV4Swaps(callbackData);

        // Get target pool and coin info
        (PoolKey memory targetPool, bool isCoinCurrency0, address coinAddress) = _getTargetPoolInfo(callbackData.v4Route, swapResult.outputCurrency);

        // Get current pool state after swap
        (uint160 sqrtPriceX96, int24 currentTick) = _getPoolState(targetPool);

        // Create limit orders
        (CreatedOrder[] memory createdOrders, uint128 unallocated) = _createLimitOrders(
            targetPool,
            isCoinCurrency0,
            coinAddress,
            swapResult.outputAmount,
            currentTick,
            sqrtPriceX96,
            callbackData.limitOrderConfig,
            callbackData.recipient
        );

        // Settle currencies with pool manager
        _settleCurrencies(callbackData.currencyReceived, callbackData.currencyAmount, coinAddress, unallocated, callbackData.recipient);

        return abi.encode(createdOrders, isCoinCurrency0, currentTick);
    }

    /// @notice Executes V4 multi-hop swaps and validates output
    /// @param callbackData The callback data containing swap parameters
    /// @return swapResult The result of the V4 swap containing output amount and currency
    function _executeV4Swaps(CallbackData memory callbackData) internal returns (V3ToV4SwapLib.V4SwapResult memory swapResult) {
        swapResult = V3ToV4SwapLib.executeV4MultiHopSwap(
            poolManager,
            V3ToV4SwapLib.V4SwapParams({
                v4Route: callbackData.v4Route,
                amountIn: callbackData.currencyAmount,
                startingCurrency: Currency.wrap(callbackData.currencyReceived)
            })
        );

        // Validate minimum output amount
        require(swapResult.outputAmount >= callbackData.minAmountOut, InsufficientOutputAmount());
    }

    /// @notice Gets target pool and coin information
    /// @param v4Route The V4 route array
    /// @param outputCurrency The output currency from swaps
    /// @return targetPool The target pool (last pool in route)
    /// @return isCoinCurrency0 Whether the coin is currency0 in the pool
    /// @return coinAddress The address of the coin
    function _getTargetPoolInfo(
        PoolKey[] memory v4Route,
        Currency outputCurrency
    ) internal pure returns (PoolKey memory targetPool, bool isCoinCurrency0, address coinAddress) {
        uint256 targetPoolIndex = v4Route.length - 1;
        targetPool = v4Route[targetPoolIndex];
        coinAddress = Currency.unwrap(outputCurrency);
        isCoinCurrency0 = Currency.unwrap(targetPool.currency0) == coinAddress;
    }

    /// @notice Gets current tick and price from pool
    /// @param targetPool The pool to query
    /// @return sqrtPriceX96 The current sqrt price
    /// @return tick The current tick
    function _getPoolState(PoolKey memory targetPool) internal view returns (uint160 sqrtPriceX96, int24 tick) {
        (sqrtPriceX96, tick, , ) = StateLibrary.getSlot0(poolManager, targetPool.toId());
    }

    /// @notice Creates limit orders with metadata from swap output
    /// @param targetPool The target pool for the orders
    /// @param isCoinCurrency0 Whether the coin is currency0
    /// @param coinAddress The address of the coin
    /// @param coinAmount The amount of coins received from swap
    /// @param currentTick The current tick after swap
    /// @param sqrtPriceX96 The current sqrt price after swap
    /// @param limitOrderConfig The limit order configuration
    /// @param maker The maker address (order owner/recipient)
    /// @return createdOrders Array of CreatedOrder structs with orderIds and config
    /// @return unallocated The amount not allocated to orders (goes to maker)
    function _createLimitOrders(
        PoolKey memory targetPool,
        bool isCoinCurrency0,
        address coinAddress,
        uint128 coinAmount,
        int24 currentTick,
        uint160 sqrtPriceX96,
        LimitOrderConfig memory limitOrderConfig,
        address maker
    ) internal returns (CreatedOrder[] memory createdOrders, uint128 unallocated) {
        uint128 allocated;
        Orders memory orders;
        // Compute limit orders
        (orders, allocated, unallocated) = SwapLimitOrders.computeOrders(targetPool, isCoinCurrency0, coinAmount, currentTick, sqrtPriceX96, limitOrderConfig);

        // Create orders if there are any to create
        if (orders.sizes.length > 0 && allocated > 0) {
            // Take allocated coins from pool manager to this contract
            poolManager.take(Currency.wrap(coinAddress), address(this), allocated);

            // Set value for ETH transfers (0 for ERC20, allocated for ETH)
            uint256 value = coinAddress != address(0) ? 0 : allocated;

            // For ERC20, approve the order book to spend the coins
            if (coinAddress != address(0)) {
                IERC20(coinAddress).approve(address(zoraLimitOrderBook), allocated);
            }

            // Create orders with prefunded path
            bytes32[] memory orderIds = zoraLimitOrderBook.create{value: value}(targetPool, isCoinCurrency0, orders.sizes, orders.ticks, maker);

            createdOrders = new CreatedOrder[](orderIds.length);
            unchecked {
                for (uint256 i; i < orderIds.length; ++i) {
                    createdOrders[i] = CreatedOrder({orderId: orderIds[i], multiple: orders.multiples[i], percentage: orders.percentages[i]});
                }
            }
        } else {
            createdOrders = new CreatedOrder[](0);
        }
    }

    /// @notice Settles input currency and distributes output coins
    /// @param inputCurrency The input currency address
    /// @param inputAmount The input currency amount
    /// @param coinAddress The coin address
    /// @param unallocated The unallocated coin amount to send to maker
    /// @param maker The maker address (buyer)
    function _settleCurrencies(address inputCurrency, uint256 inputAmount, address coinAddress, uint128 unallocated, address maker) internal {
        // Settle input currency with pool manager
        _transferFundsToPoolManager(inputCurrency, inputAmount);

        // Take unallocated coins to maker (buyer)
        if (unallocated > 0) {
            poolManager.take(Currency.wrap(coinAddress), maker, unallocated);
        }
    }

    function _transferFundsToPoolManager(address token, uint256 amount) internal {
        Currency currency = Currency.wrap(token);
        // Settle input currency
        // if erc20 currency, sync and transfer
        if (!currency.isAddressZero()) {
            poolManager.sync(currency);

            // transfer with balance check
            uint256 beforeBalance = currency.balanceOf(address(poolManager));
            currency.transfer(address(poolManager), amount);
            require(currency.balanceOf(address(poolManager)) == beforeBalance + amount, IZoraLimitOrderBook.InsufficientTransferFunds());

            poolManager.settle();
        } else {
            poolManager.settle{value: amount}();
        }
    }

    /// @notice Fills limit orders within the tick range crossed by the swap
    /// @param poolKey The pool key
    /// @param isCurrency0 Whether to fill currency0 orders
    /// @param tickBeforeSwap The tick before the swap
    /// @param tickAfterSwap The tick after the swap
    function _fillOrders(PoolKey memory poolKey, bool isCurrency0, int24 tickBeforeSwap, int24 tickAfterSwap) internal {
        // Ensure ticks are in the correct order for fill validation
        // For currency0 orders: startTick <= endTick (ascending)
        // For currency1 orders: startTick >= endTick (descending)
        int24 startTick;
        int24 endTick;
        if (isCurrency0) {
            // Currency0 orders need ascending tick range
            startTick = tickBeforeSwap < tickAfterSwap ? tickBeforeSwap : tickAfterSwap;
            endTick = tickBeforeSwap < tickAfterSwap ? tickAfterSwap : tickBeforeSwap;
        } else {
            // Currency1 orders need descending tick range
            startTick = tickBeforeSwap > tickAfterSwap ? tickBeforeSwap : tickAfterSwap;
            endTick = tickBeforeSwap > tickAfterSwap ? tickAfterSwap : tickBeforeSwap;
        }

        // Call fill in locked mode - will trigger unlock/callback flow in ZoraLimitOrderBook
        zoraLimitOrderBook.fill(poolKey, isCurrency0, startTick, endTick, 0, address(0));
    }

    /// @notice Validates that the provided config matches the canonical config
    /// @param config The config to validate
    function _validateConfigMatchesCurrent(LimitOrderConfig memory config) internal view {
        uint256 canonicalLength = _limitOrderConfig.multiples.length;

        // If canonical config is uninitialized, skip validation
        if (canonicalLength == 0) return;

        // Check array lengths match
        require(config.multiples.length == canonicalLength && config.percentages.length == canonicalLength, InvalidLimitOrderConfig());

        // Validate all values in single loop
        unchecked {
            for (uint256 i; i < canonicalLength; ++i) {
                require(
                    config.multiples[i] == _limitOrderConfig.multiples[i] && config.percentages[i] == _limitOrderConfig.percentages[i],
                    InvalidLimitOrderConfig()
                );
            }
        }
    }

    /// @notice Allows contract to receive ETH
    receive() external payable {}
}
