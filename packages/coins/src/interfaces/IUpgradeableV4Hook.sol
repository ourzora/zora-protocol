// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {LpPosition} from "../types/LpPosition.sol";

struct Delta {
    int128 token0;
    int128 token1;
}

struct MigratedLiquidityResult {
    uint160 sqrtPriceX96;
    BurnedPosition[] burnedPositions;
    uint256 totalAmount0;
    uint256 totalAmount1;
}

struct BurnedPosition {
    int24 tickLower;
    int24 tickUpper;
    uint128 amount0Received;
    uint128 amount1Received;
}

interface IUpgradeableV4Hook {
    /// @notice Migrate liquidity from this hook to a new hook
    /// @param newHook Address of the new hook implementation
    /// @param poolKey The pool key to migrate
    /// @param additionalData Additional data to pass to the new hook during initialization
    /// @return newPoolKey The new pool key returned from the destination hook
    function migrateLiquidity(address newHook, PoolKey memory poolKey, bytes calldata additionalData) external returns (PoolKey memory newPoolKey);

    error InvalidNewHook(address newHook);
    error UpgradePathNotRegistered(address oldHook, address newHook);
}

interface IUpgradeableDestinationV4Hook {
    /// @notice Initialize after migration from old hook
    /// @param poolKey The pool key being migrated
    /// @param coin The coin address
    /// @param sqrtPriceX96 The current sqrt price
    /// @param migratedLiquidity The migrated liquidity
    /// @param additionalData Additional data for initialization
    function initializeFromMigration(
        PoolKey calldata poolKey,
        address coin,
        uint160 sqrtPriceX96,
        BurnedPosition[] calldata migratedLiquidity,
        bytes calldata additionalData
    ) external;
}
