// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/// @notice ERC20Minter Helper contract template
abstract contract ERC20MinterRewards {
    uint256 internal constant MIN_PRICE_PER_TOKEN = 10_000;
    uint256 internal constant BPS_TO_PERCENT_2_DECIMAL_PERCISION = 100;
    uint256 internal constant BPS_TO_PERCENT_8_DECIMAL_PERCISION = 100_000_000;
    uint256 internal constant CREATE_REFERRAL_PAID_MINT_REWARD_PCT = 28_571400; // 28.5714%, roughly 0.000222 ETH at a 0.000777 value
    uint256 internal constant MINT_REFERRAL_PAID_MINT_REWARD_PCT = 28_571400; // 28.5714%, roughly 0.000222 ETH at a 0.000777 value
    uint256 internal constant ZORA_PAID_MINT_REWARD_PCT = 28_571400; // 28.5714%, roughly 0.000222 ETH at a 0.000777 value
    uint256 internal constant FIRST_MINTER_REWARD_PCT = 14_228500; // 14.2285%, roughly 0.000111 ETH at a 0.000777 value
}
