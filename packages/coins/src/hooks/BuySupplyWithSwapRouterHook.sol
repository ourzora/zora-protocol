// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {BaseCoinDeployHook} from "./BaseCoinDeployHook.sol";
import {ICoin} from "../interfaces/ICoin.sol";
import {IZoraFactory} from "../interfaces/IZoraFactory.sol";
import {ISwapRouter} from "../interfaces/ISwapRouter.sol";
import {IWETH} from "../interfaces/IWETH.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title BuySupplyWithSwapRouter
/// @notice A hook that buys supply for a coin that is priced in an erc20 token with ETH, using a Uniswap SwapRouter.
/// Supports both single-hop and multi-hop swaps using uniswap v3
contract BuySupplyWithSwapRouterHook is BaseCoinDeployHook {
    ISwapRouter immutable swapRouter;

    error Erc20NotReceived();
    error InvalidSwapRouterCall();
    error SwapReverted(bytes error);
    error CoinBalanceNot0(uint256 balance);

    constructor(IZoraFactory _factory, address _swapRouter) BaseCoinDeployHook(_factory) {
        swapRouter = ISwapRouter(_swapRouter);
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

        (, coinsPurchased) = coin.buy(buyRecipient, amountCurrency, 0, 0, address(0));

        // make sure that this contract has no balance of the coin remaining
        uint256 coinBalance = IERC20(address(coin)).balanceOf(address(this));
        require(coinBalance == 0, CoinBalanceNot0(coinBalance));
    }
}
