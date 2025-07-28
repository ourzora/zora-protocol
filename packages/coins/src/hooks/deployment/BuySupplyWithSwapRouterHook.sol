// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IPoolManager, SwapParams} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BaseCoinDeployHook} from "./BaseCoinDeployHook.sol";
import {ICoin} from "../../interfaces/ICoin.sol";
import {IZoraFactory} from "../../interfaces/IZoraFactory.sol";
import {ISwapRouter} from "../../interfaces/ISwapRouter.sol";
import {IWETH} from "../../interfaces/IWETH.sol";
import {ICoinV3} from "../../interfaces/ICoinV3.sol";
import {ICoin} from "../../interfaces/ICoin.sol";
import {CoinConfigurationVersions} from "../../libs/CoinConfigurationVersions.sol";

/// @title BuySupplyWithSwapRouter
/// @notice A hook that buys supply for a coin that is priced in an erc20 token a backing currency, using a Uniswap V3 SwapRouter.
/// Supports both single-hop and multi-hop swaps using uniswap v3.  Supports buying the coin supply whether the coin is a v3 or v4 coin.
/// @author @oveddan
contract BuySupplyWithSwapRouterHook is BaseCoinDeployHook {
    ISwapRouter immutable swapRouter;
    IPoolManager immutable poolManager;
    using BalanceDeltaLibrary for BalanceDelta;

    error Erc20NotReceived();
    error InvalidSwapRouterCall();
    error SwapReverted(bytes error);
    error CoinBalanceNot0(uint256 balance);
    error CurrencyBalanceNot0(uint256 balance);

    constructor(IZoraFactory _factory, address _swapRouter, address _poolManager) BaseCoinDeployHook(_factory) {
        swapRouter = ISwapRouter(_swapRouter);
        poolManager = IPoolManager(_poolManager);
    }

    /// @notice Hook that buys supply for a coin that is priced in an erc20 token with ETH, using a Uniswap SwapRouter.
    /// Returns abi encoded (uint256 amountCurrency, uint256 coinsPurchased) - amountCurrency is the amount of currency received from the swap and sent to the coin for the purchase,
    /// and coinsPurchased is the amount of coins purchased using the amountCurrency that was received from the swap
    function _afterCoinDeploy(address, ICoin coin, bytes calldata hookData) internal override returns (bytes memory) {
        address currency = coin.currency();

        (address buyRecipient, bytes memory swapRouterCall) = abi.decode(hookData, (address, bytes));

        uint256 amountCurrency = _handleSwap(currency, swapRouterCall);

        uint256 coinsPurchased = _handleBuy(buyRecipient, coin, amountCurrency);

        return abi.encode(amountCurrency, coinsPurchased);
    }

    function _handleSwap(address currency_, bytes memory swapRouterCall) internal returns (uint256 amountCurrency) {
        // call the swap router, with the msg.value
        _validateSwapRouterCall(swapRouterCall);

        (bool success, bytes memory result) = address(swapRouter).call{value: msg.value}(swapRouterCall);

        require(success, SwapReverted(result));

        amountCurrency = abi.decode(result, (uint256));

        // validate that this contract received the correct amount of currency
        require(IERC20(currency_).balanceOf(address(this)) == amountCurrency, Erc20NotReceived());
    }

    function _validateSwapRouterCall(bytes memory swapRouterCall) internal pure {
        // validate that the swap router call is valid - only exactInput and exactInputSingle are supported

        bytes4 selector = _getSelectorFromCall(swapRouterCall);

        require(selector == ISwapRouter.exactInput.selector || selector == ISwapRouter.exactInputSingle.selector, InvalidSwapRouterCall());
    }

    function _getSelectorFromCall(bytes memory _call) internal pure returns (bytes4 selector) {
        assembly {
            selector := mload(add(_call, 32))
        }
    }

    function _handleBuy(address buyRecipient, ICoin coin, uint256 amountCurrency) internal returns (uint256 coinsPurchased) {
        IERC20(coin.currency()).approve(address(coin), amountCurrency);

        if (CoinConfigurationVersions.isV4(factory.getVersionForDeployedCoin(address(coin)))) {
            coinsPurchased = _executeV4Buy(buyRecipient, ICoin(payable(address(coin))), amountCurrency);
        } else {
            coinsPurchased = _executeV3Buy(buyRecipient, ICoinV3(payable(address(coin))), amountCurrency);
        }

        // make sure that this contract has no balance of the coin remaining
        uint256 coinBalance = IERC20(address(coin)).balanceOf(address(this));
        require(coinBalance == 0, CoinBalanceNot0(coinBalance));
        // make sure that this contract has no balance of the currency remaining
        uint256 currencyBalance = IERC20(coin.currency()).balanceOf(address(this));
        require(currencyBalance == 0, CurrencyBalanceNot0(currencyBalance));
    }

    function _executeV3Buy(address buyRecipient, ICoinV3 coin, uint256 amountCurrency) internal returns (uint256 coinsPurchased) {
        (, coinsPurchased) = ICoinV3(payable(address(coin))).buy(buyRecipient, amountCurrency, 0, 0, address(0));
    }

    function _executeV4Buy(address buyRecipient, ICoin coin, uint256 amountCurrency) internal returns (uint256 coinsPurchased) {
        bytes memory data = abi.encode(buyRecipient, coin, amountCurrency);

        bytes memory result = poolManager.unlock(data);

        coinsPurchased = abi.decode(result, (uint256));
    }

    error OnlyPoolManager();

    /// @notice Internal fn called when the PoolManager is unlocked.  Used to swap the backing currency for the coin.
    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(poolManager), OnlyPoolManager());

        (address buyRecipient, ICoin coin, uint256 amountCurrency) = abi.decode(data, (address, ICoin, uint256));

        bool zeroForOne = coin.currency() == Currency.unwrap(coin.getPoolKey().currency0);

        BalanceDelta delta = poolManager.swap(
            coin.getPoolKey(),
            SwapParams(zeroForOne, -(int128(uint128(amountCurrency))), zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1),
            ""
        );

        int128 amountCoin = zeroForOne ? delta.amount1() : delta.amount0();

        // sync the currency balance before transferring to the pool manager
        poolManager.sync(Currency.wrap(coin.currency()));
        // transfer the currency to the pool manager for the swap
        SafeERC20.safeTransfer(IERC20(coin.currency()), address(poolManager), uint256(uint128(amountCurrency)));
        // collect the coin from the pool manager
        poolManager.take(Currency.wrap(address(coin)), buyRecipient, uint256(uint128(amountCoin)));

        poolManager.settle();

        return abi.encode(uint256(uint128(amountCoin)));
    }
}
