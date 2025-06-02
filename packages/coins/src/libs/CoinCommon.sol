// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

library CoinCommon {
    // Helper function to sort tokens and determine if coin is token0
    function sortTokens(address coin, address currency) internal pure returns (bool isCoinToken0) {
        return coin < currency;
    }

    function hashPoolKey(PoolKey memory key) internal pure returns (bytes32) {
        return keccak256(abi.encode(key));
    }
}
