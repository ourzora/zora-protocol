// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ICoin} from "./ICoin.sol";
import {LpPosition} from "../types/LpPosition.sol";
import {PoolConfiguration} from "./ICoin.sol";

interface ICoinV3 is ICoin {
    /// @notice Returns the WETH address
    function WETH() external view returns (address);

    /// @notice Returns the address of the Uniswap V3 factory
    function v3Factory() external view returns (address);

    /// @notice Initializes a new coin
    /// @param payoutRecipient_ The address of the coin creator
    /// @param tokenURI_ The metadata URI
    /// @param name_ The coin name
    /// @param symbol_ The coin symbol
    /// @param platformReferrer_ The address of the platform referrer
    /// @param currency_ The address of the currency
    /// @param poolAddress_ The address of the pool
    /// @param poolConfiguration_ The configuration of the pool
    function initialize(
        address payoutRecipient_,
        address[] memory owners_,
        string memory tokenURI_,
        string memory name_,
        string memory symbol_,
        address platformReferrer_,
        address currency_,
        address poolAddress_,
        PoolConfiguration memory poolConfiguration_,
        LpPosition[] memory positions_
    ) external;

    /// @notice Executes a buy order
    /// @param recipient The recipient address of the coins
    /// @param orderSize The amount of coins to buy
    /// @param tradeReferrer The address of the trade referrer
    /// @param sqrtPriceLimitX96 The price limit for Uniswap V3 pool swap
    function buy(
        address recipient,
        uint256 orderSize,
        uint256 minAmountOut,
        uint160 sqrtPriceLimitX96,
        address tradeReferrer
    ) external payable returns (uint256, uint256);

    /// @notice Executes a sell order
    /// @param recipient The recipient of the currency
    /// @param orderSize The amount of coins to sell
    /// @param minAmountOut The minimum amount of currency to receive
    /// @param sqrtPriceLimitX96 The price limit for the swap
    /// @param tradeReferrer The address of the trade referrer
    function sell(
        address recipient,
        uint256 orderSize,
        uint256 minAmountOut,
        uint160 sqrtPriceLimitX96,
        address tradeReferrer
    ) external returns (uint256, uint256);

    /// @notice Force claim any accrued secondary rewards from the market's liquidity position.
    /// @dev This function is a fallback, secondary rewards will be claimed automatically on each buy and sell.
    /// @param pushEthRewards Whether to push the ETH directly to the recipients.
    function claimSecondaryRewards(bool pushEthRewards) external;

    /// @notice Returns the address of the Uniswap V3 pool
    function poolAddress() external view returns (address);
}
