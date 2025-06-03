// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ICoin} from "./ICoin.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {LpPosition} from "../types/LpPosition.sol";
import {PoolConfiguration} from "../types/PoolConfiguration.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PathKey} from "@uniswap/v4-periphery/src/libraries/PathKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IDeployedCoinVersionLookup} from "./IDeployedCoinVersionLookup.sol";

/// @notice Returns the pool key for the coin
interface IHasPoolKey {
    function getPoolKey() external view returns (PoolKey memory);
}

/// @notice Returns the pool configuration for the coin
interface IHasSwapPath {
    struct PayoutSwapPath {
        PathKey[] path;
        Currency currencyIn;
    }

    function getPayoutSwapPath(IDeployedCoinVersionLookup coinVersionLookup) external view returns (PayoutSwapPath memory);
}

interface ICoinV4 is ICoin, IHasPoolKey, IHasSwapPath {
    function getPoolConfiguration() external view returns (PoolConfiguration memory);

    /// @notice Returns the hooks contract used by this coin
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
