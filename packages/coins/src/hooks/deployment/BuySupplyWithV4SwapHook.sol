// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {IPoolManager, SwapParams} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BaseCoinDeployHook} from "./BaseCoinDeployHook.sol";
import {IUniswapV3SwapCallback} from "../../interfaces/IUniswapV3SwapCallback.sol";
import {ICoin} from "../../interfaces/ICoin.sol";
import {ISwapRouter} from "../../interfaces/ISwapRouter.sol";
import {IZoraFactory} from "../../interfaces/IZoraFactory.sol";
import {ICoinV3} from "../../interfaces/ICoinV3.sol";
import {CoinConfigurationVersions} from "../../libs/CoinConfigurationVersions.sol";
import {TransientStateLibrary} from "@uniswap/v4-core/src/libraries/TransientStateLibrary.sol";
import {Path} from "@zoralabs/shared-contracts/libs/UniswapV3/Path.sol";

/// @title BuySupplyWithV4SwapHook
/// @notice Hook for purchasing initial coin supply with flexible swap routing
/// @dev Capabilities:
///      - ETH → V3 swap → V4 swap → coin (e.g., ETH → ZORA → Creator Coin → Content Coin)
///      - ETH → V3 swap → coin (e.g., ETH → ZORA for ZORA-backed coin)
///      - ETH → V4 swap → coin (direct ETH-paired coins)
///      - ERC20 → V4 swap → coin (e.g., Creator Coins → Content Coin)
///      - Slippage protection with minAmountOut validation
///
///      Limitations:
///      - V3 swaps only support ETH as input currency
///      - ERC20 input currencies require pre-approval
///      - V3 and V4 routes must connect properly (V3 output = V4 input)
contract BuySupplyWithV4SwapHook is BaseCoinDeployHook {
    using BalanceDeltaLibrary for BalanceDelta;
    using SafeERC20 for IERC20;
    using CurrencyLibrary for Currency;
    using Path for bytes;

    // ============ STATE VARIABLES ============

    ISwapRouter public immutable swapRouter;
    IPoolManager public immutable poolManager;

    // ============ STRUCTS ============

    struct InitialSupplyParams {
        address buyRecipient; // Who gets the coins
        bytes v3Route; // V3 route from ETH to backing currency
        PoolKey[] v4Route; // V4 route from backing currency to coin
        address inputCurrency; // Currency to use for the V3 swap
        uint256 inputAmount; // Amount of input currency to use for the V3 swap
        uint256 minAmountOut; // Minimum amount of coins to receive from final swap
    }

    event BuyInitialSupply(
        address indexed coin,
        address indexed recipient,
        uint256 indexed coinsPurchased,
        bytes v3Route,
        PoolKey[] v4Route,
        address inputCurrency,
        uint256 inputAmount,
        uint256 v4SwapInput
    );

    // ============ ERRORS ============

    error OnlyPoolManager();
    error InsufficientInputCurrency(uint256 inputAmount, uint256 availableAmount);
    error V3RouteCannotStartWithInputCurrency();
    error V3RouteDoesNotConnectToV4RouteStart();
    error InsufficientOutputAmount();

    // ============ CONSTRUCTOR ============

    constructor(IZoraFactory _factory, address _swapRouter, address _poolManager) BaseCoinDeployHook(_factory) {
        swapRouter = ISwapRouter(_swapRouter);
        poolManager = IPoolManager(_poolManager);
    }

    // ============ MAIN HOOK FUNCTION ============

    /// @notice Hook that buys supply for a coin using V3->V4 two-step swap routing
    /// @dev Returns abi encoded (uint256 amountCurrency, uint256 coinsPurchased)
    function _afterCoinDeploy(address, ICoin coin, bytes calldata hookData) internal override returns (bytes memory) {
        // STEP 1: Decode parameters
        InitialSupplyParams memory params = abi.decode(hookData, (InitialSupplyParams));

        PoolKey[] memory v4Route = _buildV4RouteToCoin(coin, params.v4Route);

        // STEP 2: Validate routes
        _validateRoutes(params, v4Route);

        _validateAndTransferInputCurrency(params);

        // STEP 3: Execute V3 swap (inputCurrency -> backing currency)
        (uint256 currencyAmount, address currencyReceived) = _executeV3Swap(params);

        // STEP 4: Execute V4 swaps if needed, then buy coin
        uint256 coinAmount = _executeV4Swap(v4Route, currencyAmount, currencyReceived, params.buyRecipient);

        // Validate minimum amount of coins received from final swap
        require(coinAmount >= params.minAmountOut, InsufficientOutputAmount());

        emit BuyInitialSupply({
            recipient: params.buyRecipient,
            coin: address(coin),
            v3Route: params.v3Route,
            v4Route: v4Route,
            inputCurrency: params.inputCurrency,
            inputAmount: params.inputAmount,
            v4SwapInput: currencyAmount,
            coinsPurchased: coinAmount
        });

        // STEP 5: Return results
        return abi.encode(currencyAmount, coinAmount);
    }

    // ============ VALIDATION ============

    function _validateRoutes(InitialSupplyParams memory params, PoolKey[] memory v4Route) internal pure {
        // Determine what currency should be the input to the V4 route
        address v4InputCurrency;
        if (params.v3Route.length == 0) {
            // No V3 swap - input currency should directly match V4 route start
            v4InputCurrency = params.inputCurrency;
        } else {
            // V3 swap exists - V3 output should match V4 route start
            v4InputCurrency = _getV3RouteOutputCurrency(params.v3Route);
        }

        PoolKey memory firstPool = v4Route[0];

        require(
            v4InputCurrency == Currency.unwrap(firstPool.currency0) || v4InputCurrency == Currency.unwrap(firstPool.currency1),
            V3RouteDoesNotConnectToV4RouteStart()
        );
    }

    function _validateAndTransferInputCurrency(InitialSupplyParams memory params) internal {
        if (params.inputCurrency == address(0)) {
            uint256 providedAmount = msg.value;

            require(providedAmount == params.inputAmount, InsufficientInputCurrency(params.inputAmount, providedAmount));
        } else {
            uint256 providedAmount = IERC20(params.inputCurrency).allowance(params.buyRecipient, address(this));

            // must be enough allowance to transfer
            require(providedAmount >= params.inputAmount, InsufficientInputCurrency(params.inputAmount, providedAmount));

            // transfer from the buy recipient to this contract
            IERC20(params.inputCurrency).safeTransferFrom(params.buyRecipient, address(this), params.inputAmount);
        }
    }

    function _buildV4RouteToCoin(ICoin coin, PoolKey[] memory v4Route) internal view returns (PoolKey[] memory fullRoute) {
        fullRoute = new PoolKey[](v4Route.length + 1);

        for (uint256 i = 0; i < v4Route.length; i++) {
            fullRoute[i] = v4Route[i];
        }

        fullRoute[v4Route.length] = coin.getPoolKey();
    }

    // ============ V3 SWAP LOGIC ============

    function _executeV3Swap(InitialSupplyParams memory params) internal returns (uint256 amountCurrency, address currencyReceived) {
        if (params.v3Route.length == 0) {
            // No V3 swap needed - return inputAmount directly
            return (params.inputAmount, params.inputCurrency);
        }

        // for v3 swap section, we dont support currently having an input currency other than eth
        if (params.inputCurrency != address(0)) {
            revert V3RouteCannotStartWithInputCurrency();
        }

        // Build swap router call for exactInput
        ISwapRouter.ExactInputParams memory swapParams = ISwapRouter.ExactInputParams({
            path: params.v3Route,
            recipient: address(this),
            amountIn: params.inputAmount,
            amountOutMinimum: 0 // For testing - in production should have slippage protection
        });

        amountCurrency = swapRouter.exactInput{value: params.inputAmount}(swapParams);

        currencyReceived = _getV3RouteOutputCurrency(params.v3Route);
    }

    function _executeV4Swap(PoolKey[] memory v4Route, uint256 amountIn, address currencyIn, address buyRecipient) internal returns (uint256 amountCoin) {
        Currency startingCurrency = Currency.wrap(currencyIn);
        bytes memory data = abi.encode(v4Route, amountIn, startingCurrency, buyRecipient);
        bytes memory result = poolManager.unlock(data);
        amountCoin = abi.decode(result, (uint256));
    }

    /// @notice Callback for V4 swaps through route or coin purchase
    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(poolManager), OnlyPoolManager());

        (PoolKey[] memory v4Route, uint256 amountIn, Currency startingCurrency, address buyRecipient) = abi.decode(
            data,
            (PoolKey[], uint256, Currency, address)
        );

        Currency lastReceivedCurrency = startingCurrency;
        uint128 lastReceivedAmount = uint128(amountIn);
        // Execute swaps through the route

        uint128 outputAmount = 0;
        for (uint256 i = 0; i < v4Route.length; i++) {
            PoolKey memory poolKey = v4Route[i];

            // Determine swap direction based on current currency
            bool zeroForOne = lastReceivedCurrency == poolKey.currency0;

            BalanceDelta delta = poolManager.swap(
                poolKey,
                SwapParams(zeroForOne, -(int128(lastReceivedAmount)), zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1),
                ""
            );

            // Extract output amount from delta
            outputAmount = zeroForOne ? uint128(delta.amount1()) : uint128(delta.amount0());

            // Update currentAmount for next iteration
            lastReceivedAmount = uint128(outputAmount);

            // Update current currency for next swap
            lastReceivedCurrency = zeroForOne ? poolKey.currency1 : poolKey.currency0;
        }

        // Settle all currency deltas and get final amount
        _settleDeltas(startingCurrency, lastReceivedCurrency, buyRecipient, amountIn, outputAmount);

        return abi.encode(lastReceivedAmount);
    }

    /// @notice Helper to decode V4 route data (external for try/catch)
    function decodeV4RouteData(bytes calldata data) external pure returns (PoolKey[] memory v4Route, uint256 startAmount) {
        return abi.decode(data, (PoolKey[], uint256));
    }

    function encodeBuySupplyWithV4SwapHookData(InitialSupplyParams memory params) external pure returns (bytes memory) {
        return abi.encode(params);
    }

    function _settleDeltas(Currency inputCurrency, Currency outputCurrency, address to, uint256 inputAmount, uint128 outputAmount) private {
        // pay the input amount
        if (inputCurrency.isAddressZero()) {
            // For ETH, settle with msg.value
            poolManager.settle{value: inputAmount}();
        } else {
            // For ERC20, sync and transfer
            poolManager.sync(inputCurrency);
            inputCurrency.transfer(address(poolManager), inputAmount);
            poolManager.settle();
        }

        // transfer the output amount to the recipient
        poolManager.take(outputCurrency, to, outputAmount);
    }

    // ============ UTILITIES ============

    function _getCoinBackingCurrency(ICoin coin) internal view returns (Currency) {
        PoolKey memory poolKey = coin.getPoolKey();

        if (Currency.unwrap(poolKey.currency0) == address(coin)) {
            return poolKey.currency1;
        }
        return poolKey.currency0;
    }

    function _getV3RouteOutputCurrency(bytes memory path) internal pure returns (address tokenOut) {
        if (path.length == 0) {
            // if no path, then output currency is eth
            return address(0);
        }

        // For a path with multiple pools, we need to traverse to the end
        // Path format: tokenA + fee + tokenB + fee + tokenC...
        // We want the final token (tokenC in this example)

        // Follow Uniswap's pattern: traverse the path to find the final token
        bytes memory currentPath = path;

        // Keep skipping tokens until we reach the final pool
        while (currentPath.hasMultiplePools()) {
            currentPath = currentPath.skipToken();
        }

        // The final segment contains the last pool, decode to get the output token
        (, tokenOut, ) = currentPath.decodeFirstPool();
    }

    function _getV3RouteInputCurrency(bytes memory path) internal pure returns (address tokenIn) {
        if (path.length == 0) {
            // if no path, then input currency is eth
            return address(0);
        }

        // Use Path library to get the input token (first token in the path)
        (tokenIn, , ) = path.decodeFirstPool();
    }
}
