// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

library MarketConstants {
    /// @dev Constant used to increase precision during calculations
    uint256 constant WAD = 1e18;

    /// @notice The LP fee
    /// @dev 10000 basis points = 1%
    uint24 internal constant LP_FEE = 10000;

    /// @notice The LP fee
    /// @dev 30000 basis points = 3%
    uint24 internal constant LP_FEE_V4 = 30000;

    /// @notice The spacing for 1% pools
    /// @dev 200 ticks
    int24 internal constant TICK_SPACING = 200;

    /// @notice The minimum lower tick for legacy single LP WETH pools
    int24 internal constant LP_TICK_LOWER_WETH = -208200;

    /// @notice The upper tick for legacy single LP WETH pools
    int24 internal constant LP_TICK_UPPER = 887200;
}
