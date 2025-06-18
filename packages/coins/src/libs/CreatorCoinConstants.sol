// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

library CreatorCoinConstants {
    uint256 internal constant TOTAL_SUPPLY = 1_000_000_000e18; // 1b coins
    uint256 internal constant MARKET_SUPPLY = 500_000_000e18; // 500m coins
    uint256 internal constant CREATOR_VESTING_SUPPLY = 500_000_000e18; // 500m coins
    uint256 internal constant CREATOR_VESTING_DURATION = 5 * 365 days; // 5 years
    address internal constant CURRENCY = 0x1111111111166b7FE7bd91427724B487980aFc69;
}
