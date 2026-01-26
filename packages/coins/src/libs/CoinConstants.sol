// SPDX-License-Identifier: ZORA-DELAYED-OSL-v1
// This software is licensed under the Zora Delayed Open Source License.
// Under this license, you may use, copy, modify, and distribute this software for
// non-commercial purposes only. Commercial use and competitive products are prohibited
// until the "Open Date" (3 years from first public distribution or earlier at Zora's discretion),
// at which point this software automatically becomes available under the MIT License.
// Full license terms available at: https://docs.zora.co/coins/license
pragma solidity ^0.8.23;

library CoinConstants {
    /// @dev Slot for transiently storing the tick before a swap.
    bytes32 internal constant _BEFORE_SWAP_TICK_SLOT = keccak256("ZoraV4CoinHook.beforeSwap.tick");

    /// @dev Constant used to indicate the max fill count for limit orders
    uint256 internal constant SENTINEL_DEFAULT_LIMIT_ORDER_FILL_COUNT = 0;

    /// @dev Constant used to increase precision during calculations
    uint256 internal constant WAD = 1e18;

    /// @notice The maximum total supply
    /// @dev Set to 1 billion coins with 18 decimals
    uint256 internal constant MAX_TOTAL_SUPPLY = 1_000_000_000e18;

    /// @notice The total supply for creator coins (same as MAX_TOTAL_SUPPLY)
    /// @dev 1 billion coins
    uint256 internal constant TOTAL_SUPPLY = 1_000_000_000e18;

    /// @notice The number of coins allocated to the liquidity pool for content coins
    /// @dev 990 million coins
    uint256 internal constant CONTENT_COIN_MARKET_SUPPLY = 990_000_000e18;

    /// @notice The number of coins allocated to the liquidity pool for creator coins
    /// @dev 500 million coins
    uint256 internal constant CREATOR_COIN_MARKET_SUPPLY = 500_000_000e18;

    /// @notice The number of coins rewarded to the creator for content coins on launch
    /// @dev 10 million coins
    uint256 internal constant CONTENT_COIN_INITIAL_CREATOR_SUPPLY = TOTAL_SUPPLY - CONTENT_COIN_MARKET_SUPPLY;

    /// @notice Creator coin vesting supply for creator
    /// @dev 500 million coins
    uint256 internal constant CREATOR_COIN_CREATOR_VESTING_SUPPLY = TOTAL_SUPPLY - CREATOR_COIN_MARKET_SUPPLY;

    /// @notice Creator coin vesting duration
    /// @dev 5 years with leap years accounted for
    uint256 internal constant CREATOR_VESTING_DURATION = (5 * 365.25 days);

    /// @notice The backing currency for creator coins
    /// @dev ETH backing currency address
    address internal constant CREATOR_COIN_CURRENCY = 0x1111111111166b7FE7bd91427724B487980aFc69;

    /// @notice The LP fee
    /// @dev 10000 basis points = 1%
    uint24 internal constant LP_FEE_V4 = 10_000;

    /// @notice Flag to enable dynamic fees for the pool
    /// @dev When set in pool key fee, enables hook to override fee per-swap
    uint24 internal constant DYNAMIC_FEE_FLAG = 0x800000;

    /// @notice Flag to override the fee in beforeSwap return value
    /// @dev Combined with fee value to signal V4 to use the returned fee
    uint24 internal constant OVERRIDE_FEE_FLAG = 0x400000;

    /// @notice Starting fee for launch fee (99%)
    /// @dev 990,000 pips = 99% (1,000,000 pips = 100%)
    uint24 internal constant LAUNCH_FEE_START = 990_000;

    /// @notice Duration over which launch fee decays from start to end fee
    /// @dev 10 seconds
    uint256 internal constant LAUNCH_FEE_DURATION = 10 seconds;

    /// @notice The spacing for 1% pools
    /// @dev 200 ticks
    int24 internal constant TICK_SPACING = 200;

    // Creator gets 62.5% of market rewards (0.50% of total 1% fee)
    // Market rewards = 80% of total fee (0.80% of 1%)
    uint256 internal constant CREATOR_REWARD_BPS = 6250;

    // Platform referrer gets 25% of market rewards (0.20% of total 1% fee)
    uint256 internal constant CREATE_REFERRAL_REWARD_BPS = 2500;

    // Trade referrer gets 5% of market rewards (0.04% of total 1% fee)
    uint256 internal constant TRADE_REFERRAL_REWARD_BPS = 500;

    // Doppler gets 1.25% of market rewards (0.01% of total 1% fee)
    uint256 internal constant DOPPLER_REWARD_BPS = 125;

    // LPs get 20% of total fee (0.20% of 1%)
    uint256 internal constant LP_REWARD_BPS = 2000;

    int24 internal constant DEFAULT_DISCOVERY_TICK_LOWER = -777000;
    int24 internal constant DEFAULT_DISCOVERY_TICK_UPPER = 222000;
    uint16 internal constant DEFAULT_NUM_DISCOVERY_POSITIONS = 10; // will be 11 total with tail position
    uint256 internal constant DEFAULT_DISCOVERY_SUPPLY_SHARE = 0.495e18; // half of the 990m total pool supply
}
