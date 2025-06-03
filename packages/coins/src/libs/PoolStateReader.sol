// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";

library PoolStateReader {
    function getSqrtPriceX96(PoolKey memory key, IPoolManager poolManager) internal view returns (uint160 sqrtPriceX96) {
        PoolId poolId = key.toId();
        (sqrtPriceX96, , , ) = StateLibrary.getSlot0(poolManager, poolId);
    }
}
