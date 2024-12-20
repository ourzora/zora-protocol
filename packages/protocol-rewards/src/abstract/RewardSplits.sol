// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IProtocolRewards} from "@zoralabs/shared-contracts/interfaces/IProtocolRewards.sol";
import {IRewardSplits} from "../interfaces/IRewardSplits.sol";

library RewardSplitsLib {
    uint256 internal constant BPS_TO_PERCENT = 10_0000000;
    uint256 internal constant TOTAL_REWARD_PER_MINT_PCT = 10_0000000;

    uint256 internal constant CREATOR_REWARD_PCT = 42_857100; // 42.8571%, roughly 0.000333 ETH at a 0.000777 value
    uint256 internal constant FIRST_MINTER_REWARD_PCT = 14_228500; // 14.2285%, roughly 0.000111 ETH at a 0.000777 value

    uint256 internal constant CREATE_REFERRAL_FREE_MINT_REWARD_PCT = 14_228500; // 14.2285%, roughly 0.000111 ETH at a 0.000777 value
    uint256 internal constant MINT_REFERRAL_FREE_MINT_REWARD_PCT = 14_228500; // 14.2285%, roughly 0.000111 ETH at a 0.000777 value
    uint256 internal constant ZORA_FREE_MINT_REWARD_PCT = 14_228500; // 14.2285%, roughly 0.000111 ETH at a 0.000777 value

    uint256 internal constant CREATE_REFERRAL_PAID_MINT_REWARD_PCT = 28_571400; // 28.5714%, roughly 0.000222 ETH at a 0.000777 value
    uint256 internal constant MINT_REFERRAL_PAID_MINT_REWARD_PCT = 28_571400; // 28.5714%, roughly 0.000222 ETH at a 0.000777 value
    uint256 internal constant ZORA_PAID_MINT_REWARD_PCT = 28_571400; // 28.5714%, roughly 0.000222 ETH at a 0.000777 value

    function computeRewardsPct(uint256 totalReward, uint256 rewardPct) internal pure returns (uint256) {
        return (totalReward * rewardPct) / BPS_TO_PERCENT;
    }

    function getRewardsSettingsPct(bool paidMint) private pure returns (IRewardSplits.RewardsSettings memory rewardSettings) {
        rewardSettings.creatorReward = paidMint ? 0 : CREATOR_REWARD_PCT;
        rewardSettings.createReferralReward = paidMint ? CREATE_REFERRAL_PAID_MINT_REWARD_PCT : CREATE_REFERRAL_FREE_MINT_REWARD_PCT;
        rewardSettings.mintReferralReward = paidMint ? MINT_REFERRAL_PAID_MINT_REWARD_PCT : MINT_REFERRAL_FREE_MINT_REWARD_PCT;
        rewardSettings.firstMinterReward = FIRST_MINTER_REWARD_PCT;
        // do we need this? since its recalculated below?
        // rewardSettings.zoraReward = totalReward - (rewardSettings.creatorReward + rewardSettings.createReferralReward + rewardSettings.mintReferralReward + rewardSettings.firstMinterReward);
    }

    function getRewards(bool paidMint, uint256 totalReward) internal pure returns (IRewardSplits.RewardsSettings memory rewardSettings) {
        rewardSettings = getRewardsSettingsPct(paidMint);
        rewardSettings.creatorReward = computeRewardsPct(totalReward, rewardSettings.creatorReward);
        rewardSettings.createReferralReward = computeRewardsPct(totalReward, rewardSettings.createReferralReward);
        rewardSettings.mintReferralReward = computeRewardsPct(totalReward, rewardSettings.mintReferralReward);
        rewardSettings.firstMinterReward = computeRewardsPct(totalReward, rewardSettings.firstMinterReward);
        rewardSettings.zoraReward =
            totalReward -
            (rewardSettings.creatorReward + rewardSettings.createReferralReward + rewardSettings.mintReferralReward + rewardSettings.firstMinterReward);
    }
}

/// @notice Common logic for between Zora ERC-721 & ERC-1155 contracts for protocol reward splits & deposits
abstract contract RewardSplits is IRewardSplits {
    address internal immutable zoraRewardRecipient;
    IProtocolRewards internal immutable protocolRewards;

    constructor(address _protocolRewards, address _zoraRewardRecipient) payable {
        if (_protocolRewards == address(0) || _zoraRewardRecipient == address(0)) {
            revert INVALID_ADDRESS_ZERO();
        }

        protocolRewards = IProtocolRewards(_protocolRewards);
        zoraRewardRecipient = _zoraRewardRecipient;
    }

    function computeTotalReward(uint256 mintPrice, uint256 quantity) public pure returns (uint256) {
        return mintPrice * quantity;
    }
}
