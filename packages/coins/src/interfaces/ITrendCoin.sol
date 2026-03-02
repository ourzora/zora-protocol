// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolConfiguration} from "../types/PoolConfiguration.sol";
import {ITrendCoinErrors} from "./ITrendCoinErrors.sol";

interface ITrendCoin is ITrendCoinErrors {
    /// @notice Thrown when an operation is attempted by an entity other than the metadata manager
    error OnlyMetadataManager();

    /// @notice Initializes a trend coin with simplified parameters
    /// @dev Ticker validation, URI generation, and name derivation happen internally
    /// @param owners_ Array of owner addresses for the coin
    /// @param symbol_ The ticker symbol (also used as name)
    /// @param poolKey_ The Uniswap V4 pool key
    /// @param sqrtPriceX96 The initial sqrt price for the pool
    /// @param poolConfiguration_ The pool configuration settings
    function initializeTrendCoin(
        address[] memory owners_,
        string memory symbol_,
        PoolKey memory poolKey_,
        uint160 sqrtPriceX96,
        PoolConfiguration memory poolConfiguration_
    ) external;
}
