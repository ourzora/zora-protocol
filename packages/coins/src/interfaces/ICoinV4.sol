// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ICoin} from "./ICoin.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolConfiguration} from "../types/PoolConfiguration.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PathKey} from "@uniswap/v4-periphery/src/libraries/PathKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IDeployedCoinVersionLookup} from "./IDeployedCoinVersionLookup.sol";

/// @notice Returns the pool key for the coin
interface IHasPoolKey {
    /// @notice Returns the Uniswap V4 pool key associated with this coin
    /// @return The PoolKey struct containing pool identification parameters
    function getPoolKey() external view returns (PoolKey memory);
}

/// @notice Returns the pool configuration for the coin
interface IHasSwapPath {
    /// @notice Struct containing the swap path configuration for converting fees to payout currency
    /// @param path Array of PathKey structs defining the multi-hop swap route
    /// @param currencyIn The input currency to start the swap path from
    struct PayoutSwapPath {
        PathKey[] path;
        Currency currencyIn;
    }

    /// @notice Returns the swap path configuration for converting this coin to its final payout currency
    /// @dev This enables multi-hop swaps through intermediate currencies to reach the target payout token
    /// @param coinVersionLookup Contract for looking up deployed coin versions to build recursive paths
    /// @return PayoutSwapPath struct containing the complete swap route configuration
    function getPayoutSwapPath(IDeployedCoinVersionLookup coinVersionLookup) external view returns (PayoutSwapPath memory);
}

interface ICoinV4 is ICoin, IHasPoolKey, IHasSwapPath {
    /// @notice Returns the pool configuration settings for this coin's Uniswap V4 pool
    /// @return PoolConfiguration struct containing pool-specific settings and parameters
    function getPoolConfiguration() external view returns (PoolConfiguration memory);

    /// @notice Emitted when a hook is upgraded
    /// @param fromPoolKey The pool key being upgraded
    /// @param toPoolKey The new pool key returned from the destination hook
    event LiquidityMigrated(PoolKey fromPoolKey, bytes32 fromPoolKeyHash, PoolKey toPoolKey, bytes32 toPoolKeyHash);

    /// @notice Returns the hooks contract used by this coin's Uniswap V4 pool
    /// @return The IHooks contract interface that handles pool lifecycle events
    function hooks() external view returns (IHooks);

    /// @notice Initializes the coin
    /// @dev Called by the factory contract when the contract is deployed.
    /// @param payoutRecipient_ The address of the payout recipient. Can be updated by the owner. Cannot be 0 address.
    /// @param owners_ The addresses of the owners. All owners have the same full admin access. Cannot be 0 address.
    /// @param tokenURI_ The URI of the token. Can be updated by the owner.
    /// @param name_ The name of the token. Cannot be updated.
    /// @param symbol_ The symbol of the token. Cannot be updated.
    /// @param platformReferrer_ The address of the platform referrer. Cannot be updated.
    /// @param currency_ The currency of the coin. Cannot be updated. Can be the zero address for ETH.
    /// @param poolKey_ The pool key for the coin. Derived in the factory.
    /// @param sqrtPriceX96 The initial sqrt price for the pool
    /// @param poolConfiguration_ The configuration for the pool
    function initialize(
        address payoutRecipient_,
        address[] memory owners_,
        string memory tokenURI_,
        string memory name_,
        string memory symbol_,
        address platformReferrer_,
        address currency_,
        PoolKey memory poolKey_,
        uint160 sqrtPriceX96,
        PoolConfiguration memory poolConfiguration_
    ) external;
}
