// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IRewardsErrors {
    error CREATOR_FUNDS_RECIPIENT_NOT_SET();
    error INVALID_ADDRESS_ZERO();
    error INVALID_ETH_AMOUNT();
    error ONLY_CREATE_REFERRAL();
}

interface IRewardSplits is IRewardsErrors {
    struct RewardsSettings {
        uint256 creatorReward;
        uint256 createReferralReward;
        uint256 mintReferralReward;
        uint256 firstMinterReward;
        uint256 zoraReward;
    }
}
