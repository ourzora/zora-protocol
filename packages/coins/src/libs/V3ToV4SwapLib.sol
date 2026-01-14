// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {IPoolManager, SwapParams} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {ISwapRouter} from "../interfaces/ISwapRouter.sol";
import {Path} from "@zoralabs/shared-contracts/libs/UniswapV3/Path.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {SafeCast160} from "permit2/src/libraries/SafeCast160.sol";

/// @title V3ToV4SwapLib
/// @notice Shared library for executing V3-to-V4 swap routing
/// @dev Provides common functionality for:
///      - V3 route validation and connection to V4 routes
///      - Input currency validation and transfer (ETH vs ERC20)
///      - V3 swap execution via ISwapRouter.exactInput()
///      - V4 multi-hop swap execution
///      - Delta settlement with poolManager
///      - V3 route parsing utilities
library V3ToV4SwapLib {
    using SafeERC20 for IERC20;
    using BalanceDeltaLibrary for BalanceDelta;
    using CurrencyLibrary for Currency;
    using Path for bytes;
    using SafeCast160 for uint256;

    // ============ ERRORS ============

    error InsufficientInputCurrency(uint256 inputAmount, uint256 availableAmount);
    error V3RouteCannotStartWithInputCurrency();
    error V3RouteDoesNotConnectToV4RouteStart();

    // ============ STRUCTS ============

    /// @notice Parameters for V3 swap execution
    struct V3SwapParams {
        bytes v3Route; // V3 route path
        address inputCurrency; // Input currency (address(0) for ETH)
        uint256 inputAmount; // Amount of input currency
        address recipient; // Recipient of swap output
    }

    /// @notice Parameters for V4 multi-hop swap execution
    struct V4SwapParams {
        PoolKey[] v4Route; // Array of pool keys to swap through
        uint256 amountIn; // Starting amount
        Currency startingCurrency; // Starting currency
    }

    /// @notice Result from V4 multi-hop swap
    struct V4SwapResult {
        uint128 outputAmount; // Final output amount
        Currency outputCurrency; // Final output currency
        BalanceDelta targetPoolDelta; // Delta from final (target) pool swap
    }

    // ============ VALIDATION ============

    /// @notice Validates that V3 route output connects to V4 route start
    /// @param v3Route The V3 route path (empty if no V3 swap)
    /// @param inputCurrency The input currency for the swap
    /// @param v4Route The V4 route (first pool must accept V3 output or input currency)
    function validateRoutes(bytes memory v3Route, address inputCurrency, PoolKey[] memory v4Route) internal pure {
        if (v4Route.length == 0) {
            return; // No V4 route to validate
        }

        // Determine what currency should be the input to the V4 route
        address v4InputCurrency;
        if (v3Route.length == 0) {
            // No V3 swap - input currency should directly match V4 route start
            v4InputCurrency = inputCurrency;
        } else {
            // V3 swap exists - V3 output should match V4 route start
            v4InputCurrency = getV3RouteOutputCurrency(v3Route);
        }

        PoolKey memory firstPool = v4Route[0];

        require(
            v4InputCurrency == Currency.unwrap(firstPool.currency0) || v4InputCurrency == Currency.unwrap(firstPool.currency1),
            V3RouteDoesNotConnectToV4RouteStart()
        );
    }

    /// @notice Validates and transfers input currency from sender to contract
    /// @param inputCurrency The input currency address (address(0) for ETH)
    /// @param inputAmount The amount to transfer
    /// @param from The address to transfer from
    /// @param msgValue The msg.value sent with the transaction
    function validateAndTransferInputCurrency(address inputCurrency, uint256 inputAmount, address from, uint256 msgValue) internal {
        if (inputCurrency == address(0)) {
            // ETH payment
            require(msgValue == inputAmount, InsufficientInputCurrency(inputAmount, msgValue));
        } else {
            // ERC20 payment
            uint256 allowanceAmount = IERC20(inputCurrency).allowance(from, address(this));
            require(allowanceAmount >= inputAmount, InsufficientInputCurrency(inputAmount, allowanceAmount));

            uint256 balanceAmount = IERC20(inputCurrency).balanceOf(from);
            require(balanceAmount >= inputAmount, InsufficientInputCurrency(inputAmount, balanceAmount));

            IERC20(inputCurrency).safeTransferFrom(from, address(this), inputAmount);
        }
    }

    /// @notice Validates and transfers input currency from sender using Permit2
    /// @param permit2 The Permit2 contract
    /// @param inputCurrency The input currency address (address(0) for ETH)
    /// @param inputAmount The amount to transfer
    /// @param from The address to transfer from
    /// @param to The address to transfer to (recipient)
    /// @param msgValue The msg.value sent with the transaction
    function permit2TransferFrom(IAllowanceTransfer permit2, address inputCurrency, uint256 inputAmount, address from, address to, uint256 msgValue) internal {
        if (inputCurrency == address(0)) {
            // ETH payment - no Permit2 needed
            require(msgValue == inputAmount, InsufficientInputCurrency(inputAmount, msgValue));
        } else {
            // ERC20 payment via Permit2
            require(msgValue == 0, InsufficientInputCurrency(0, msgValue));
            permit2.transferFrom(from, to, inputAmount.toUint160(), inputCurrency);
        }
    }

    // ============ V3 SWAP LOGIC ============

    /// @notice Executes a V3 swap if v3Route is provided, otherwise returns input
    /// @param swapRouter The Uniswap V3 swap router
    /// @param params The V3 swap parameters
    /// @return amountCurrency The amount received from V3 swap (or input if no swap)
    /// @return currencyReceived The currency received (output of V3 or input if no swap)
    function executeV3Swap(ISwapRouter swapRouter, V3SwapParams memory params) internal returns (uint256 amountCurrency, address currencyReceived) {
        if (params.v3Route.length == 0) {
            // No V3 swap needed - return input directly
            return (params.inputAmount, params.inputCurrency);
        }

        // Handle ERC20 input - approve swapRouter to spend tokens
        if (params.inputCurrency != address(0)) {
            IERC20(params.inputCurrency).safeIncreaseAllowance(address(swapRouter), params.inputAmount);
        }

        // Build swap router call for exactInput
        ISwapRouter.ExactInputParams memory swapParams = ISwapRouter.ExactInputParams({
            path: params.v3Route,
            recipient: params.recipient,
            amountIn: params.inputAmount,
            amountOutMinimum: 0 // Slippage protection should be handled at higher level
        });

        // Conditional value passing - ETH if inputCurrency is address(0), otherwise 0
        uint256 value = params.inputCurrency == address(0) ? params.inputAmount : 0;
        amountCurrency = swapRouter.exactInput{value: value}(swapParams);
        currencyReceived = getV3RouteOutputCurrency(params.v3Route);
    }

    // ============ V4 SWAP LOGIC ============

    /// @notice Executes a multi-hop V4 swap through multiple pools
    /// @param poolManager The Uniswap V4 pool manager
    /// @param params The V4 swap parameters
    /// @return result The swap result containing output amount and currency
    function executeV4MultiHopSwap(IPoolManager poolManager, V4SwapParams memory params) internal returns (V4SwapResult memory result) {
        Currency currentCurrency = params.startingCurrency;
        uint128 currentAmount = uint128(params.amountIn);
        BalanceDelta lastDelta;

        // Execute swaps through the route
        for (uint256 i = 0; i < params.v4Route.length; i++) {
            PoolKey memory poolKey = params.v4Route[i];

            // Determine swap direction based on current currency
            bool zeroForOne = currentCurrency == poolKey.currency0;

            lastDelta = poolManager.swap(
                poolKey,
                SwapParams(zeroForOne, -(int128(currentAmount)), zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1),
                ""
            );

            // Extract output amount from delta
            uint128 outputAmount = zeroForOne ? uint128(lastDelta.amount1()) : uint128(lastDelta.amount0());

            // Update for next iteration
            currentAmount = outputAmount;
            currentCurrency = zeroForOne ? poolKey.currency1 : poolKey.currency0;
        }

        result.outputAmount = currentAmount;
        result.outputCurrency = currentCurrency;
        result.targetPoolDelta = lastDelta;
    }

    // ============ DELTA SETTLEMENT ============

    /// @notice Settles currency deltas with the pool manager
    /// @param poolManager The Uniswap V4 pool manager
    /// @param inputCurrency The input currency to settle
    /// @param outputCurrency The output currency to take
    /// @param to The recipient of the output currency
    /// @param inputAmount The amount of input currency to settle
    /// @param outputAmount The amount of output currency to take
    function settleDeltas(
        IPoolManager poolManager,
        Currency inputCurrency,
        Currency outputCurrency,
        address to,
        uint256 inputAmount,
        uint128 outputAmount
    ) internal {
        // Pay the input amount
        if (inputCurrency.isAddressZero()) {
            // For ETH, settle with msg.value
            poolManager.settle{value: inputAmount}();
        } else {
            // For ERC20, sync and transfer
            poolManager.sync(inputCurrency);
            inputCurrency.transfer(address(poolManager), inputAmount);
            poolManager.settle();
        }

        // Transfer the output amount to the recipient
        poolManager.take(outputCurrency, to, outputAmount);
    }

    // ============ UTILITIES ============

    /// @notice Gets the output currency from a V3 route path
    /// @param path The V3 route path
    /// @return tokenOut The output token address
    function getV3RouteOutputCurrency(bytes memory path) internal pure returns (address tokenOut) {
        if (path.length == 0) {
            return address(0);
        }

        // Traverse to the end of the path to find the final token
        bytes memory currentPath = path;

        // Keep skipping tokens until we reach the final pool
        while (currentPath.hasMultiplePools()) {
            currentPath = currentPath.skipToken();
        }

        // The final segment contains the last pool, decode to get the output token
        (, tokenOut, ) = currentPath.decodeFirstPool();
    }

    /// @notice Gets the input currency from a V3 route path
    /// @param path The V3 route path
    /// @return tokenIn The input token address
    function getV3RouteInputCurrency(bytes memory path) internal pure returns (address tokenIn) {
        if (path.length == 0) {
            return address(0);
        }

        // Use Path library to get the input token (first token in the path)
        (tokenIn, , ) = path.decodeFirstPool();
    }
}
