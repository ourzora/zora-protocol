// SPDX-License-Identifier: ZORA-DELAYED-OSL-v1
// This software is licensed under the Zora Delayed Open Source License.
// Under this license, you may use, copy, modify, and distribute this software for
// non-commercial purposes only. Commercial use and competitive products are prohibited
// until the "Open Date" (3 years from first public distribution or earlier at Zora's discretion),
// at which point this software automatically becomes available under the MIT License.
// Full license terms available at: https://docs.zora.co/coins/license
pragma solidity ^0.8.23;

library CreatorCoinConstants {
    uint256 internal constant TOTAL_SUPPLY = 1_000_000_000e18; // 1b coins
    uint256 internal constant CREATOR_VESTING_SUPPLY = 500_000_000e18; // 500m coins
    uint256 internal constant CREATOR_VESTING_DURATION = 5 * 365 days; // 5 years
    address internal constant CURRENCY = 0x1111111111166b7FE7bd91427724B487980aFc69;
}
