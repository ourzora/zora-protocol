// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {LimitOrderConfig} from "../libs/SwapLimitOrders.sol";

/// @title ISetLimitOrderConfig
/// @notice Interface for setting limit order configuration
interface ISetLimitOrderConfig {
    /// @notice Sets the canonical limit order configuration
    /// @param config The new limit order configuration
    function setLimitOrderConfig(LimitOrderConfig memory config) external;
}
