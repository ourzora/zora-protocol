// SPDX-License-Identifier: ZORA-DELAYED-OSL-v1
// This software is licensed under the Zora Delayed Open Source License.
// Under this license, you may use, copy, modify, and distribute this software for
// non-commercial purposes only. Commercial use and competitive products are prohibited
// until the "Open Date" (3 years from first public distribution or earlier at Zora's discretion),
// at which point this software automatically becomes available under the MIT License.
// Full license terms available at: https://docs.zora.co/coins/license
pragma solidity ^0.8.23;

import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";

/// @title PoolStateReader
/// @notice Library for reading state information from Uniswap V4 pools
/// @dev Provides utility functions to extract specific pool state data without requiring full slot0 information
library PoolStateReader {
    /// @notice Retrieves the current square root price from a Uniswap V4 pool
    /// @dev Gets the sqrtPriceX96 value from slot0 of the specified pool, discarding other slot0 data
    /// @param key The PoolKey struct identifying the specific pool to query
    /// @param poolManager The IPoolManager contract instance to query pool state from
    /// @return sqrtPriceX96 The current square root price of the pool in X96 fixed-point format
    function getSqrtPriceX96(PoolKey memory key, IPoolManager poolManager) internal view returns (uint160 sqrtPriceX96) {
        PoolId poolId = key.toId();
        (sqrtPriceX96, , , ) = StateLibrary.getSlot0(poolManager, poolId);
    }
}
