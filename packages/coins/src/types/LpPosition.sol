// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

struct LpPosition {
    int24 tickLower;
    int24 tickUpper;
    uint128 liquidity;
}
