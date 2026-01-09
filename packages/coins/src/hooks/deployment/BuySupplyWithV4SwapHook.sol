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
import {V3ToV4SwapLib} from "../../libs/V3ToV4SwapLib.sol";

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
        V3ToV4SwapLib.validateRoutes(params.v3Route, params.inputCurrency, v4Route);

        V3ToV4SwapLib.validateAndTransferInputCurrency(params.inputCurrency, params.inputAmount, params.buyRecipient, msg.value);

        // STEP 3: Execute V3 swap (inputCurrency -> backing currency)
        (uint256 currencyAmount, address currencyReceived) = V3ToV4SwapLib.executeV3Swap(
            swapRouter,
            V3ToV4SwapLib.V3SwapParams({
                v3Route: params.v3Route,
                inputCurrency: params.inputCurrency,
                inputAmount: params.inputAmount,
                recipient: address(this)
            })
        );

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

    function _buildV4RouteToCoin(ICoin coin, PoolKey[] memory v4Route) internal view returns (PoolKey[] memory fullRoute) {
        fullRoute = new PoolKey[](v4Route.length + 1);

        for (uint256 i = 0; i < v4Route.length; i++) {
            fullRoute[i] = v4Route[i];
        }

        fullRoute[v4Route.length] = coin.getPoolKey();
    }

    // ============ V4 SWAP LOGIC ============

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

        // Execute V4 multi-hop swap
        V3ToV4SwapLib.V4SwapResult memory result = V3ToV4SwapLib.executeV4MultiHopSwap(
            poolManager,
            V3ToV4SwapLib.V4SwapParams({v4Route: v4Route, amountIn: amountIn, startingCurrency: startingCurrency})
        );

        // Settle all currency deltas and get final amount
        V3ToV4SwapLib.settleDeltas(poolManager, startingCurrency, result.outputCurrency, buyRecipient, amountIn, result.outputAmount);

        return abi.encode(result.outputAmount);
    }

    /// @notice Helper to decode V4 route data (external for try/catch)
    function decodeV4RouteData(bytes calldata data) external pure returns (PoolKey[] memory v4Route, uint256 startAmount) {
        return abi.decode(data, (PoolKey[], uint256));
    }

    function encodeBuySupplyWithV4SwapHookData(InitialSupplyParams memory params) external pure returns (bytes memory) {
        return abi.encode(params);
    }

    // ============ UTILITIES ============

    function _getCoinBackingCurrency(ICoin coin) internal view returns (Currency) {
        PoolKey memory poolKey = coin.getPoolKey();

        if (Currency.unwrap(poolKey.currency0) == address(coin)) {
            return poolKey.currency1;
        }
        return poolKey.currency0;
    }
}
