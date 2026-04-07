// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

interface ISwapPathRouter {
    struct Path {
        PoolKey key;
        Currency currencyIn;
    }

    function getSwapPath(PoolKey memory key, Currency toSwapOut) external view returns (Path[] memory path);
}
