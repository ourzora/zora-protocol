// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IZoraLimitOrderBookCoinsInterface} from "../../src/interfaces/IZoraLimitOrderBookCoinsInterface.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

/// @title MockZoraLimitOrderBook
/// @notice Mock implementation of IZoraLimitOrderBookCoinsInterface for testing purposes
contract MockZoraLimitOrderBook is IZoraLimitOrderBookCoinsInterface {
    /// @notice Fills limit orders within a tick window (mock implementation does nothing)
    function fill(PoolKey calldata, bool, int24, int24, uint256, address) external override {
        // Mock implementation - does nothing
    }
}
