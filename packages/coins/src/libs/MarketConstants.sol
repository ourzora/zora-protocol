// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

library MarketConstants {
    /// @dev Constant used to increase precision during calculations
    uint256 internal constant WAD = 1e18;

    /// @notice The number of coins allocated to the liquidity pool for content coins
    /// @dev 990 million coins
    uint256 internal constant CONTENT_COIN_MARKET_SUPPLY = 990_000_000 * WAD;

    /// @notice The number of coins allocated to the liquidity pool for creator coins
    /// @dev 500 million coins
    uint256 internal constant CREATOR_COIN_MARKET_SUPPLY = 500_000_000 * WAD;

    /// @notice The LP fee
    /// @dev 10000 basis points = 1%
    uint24 internal constant LP_FEE_V4 = 10_000;

    /// @notice The spacing for 1% pools
    /// @dev 200 ticks
    int24 internal constant TICK_SPACING = 200;
}
