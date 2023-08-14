// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IProtocolRewards} from "@zoralabs/protocol-rewards/src/interfaces/IProtocolRewards.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

struct RewardsSettings {
    uint256 creatorReward;
    uint256 createReferralReward;
    uint256 mintReferralReward;
    uint256 firstMinterReward;
    uint256 zoraReward;
}

/// @notice Common logic for between Zora ERC-721 & ERC-1155 contracts for protocol reward splits & deposits
library RewardSplits {
    error CREATOR_FUNDS_RECIPIENT_NOT_SET();
    error INVALID_ADDRESS_ZERO();
    error INVALID_ETH_AMOUNT();
    error ONLY_CREATE_REFERRAL();

    uint256 internal constant TOTAL_REWARD_PER_MINT = 0.000777 ether;

    uint256 internal constant CREATOR_REWARD = 0.000333 ether;
    uint256 internal constant FIRST_MINTER_REWARD = 0.000111 ether;

    uint256 internal constant CREATE_REFERRAL_FREE_MINT_REWARD = 0.000111 ether;
    uint256 internal constant MINT_REFERRAL_FREE_MINT_REWARD = 0.000111 ether;
    uint256 internal constant ZORA_FREE_MINT_REWARD = 0.000111 ether;

    uint256 internal constant MINT_REFERRAL_PAID_MINT_REWARD = 0.000222 ether;
    uint256 internal constant CREATE_REFERRAL_PAID_MINT_REWARD = 0.000222 ether;
    uint256 internal constant ZORA_PAID_MINT_REWARD = 0.000222 ether;

    function computeTotalReward(uint256 numTokens) public pure returns (uint256) {
        return numTokens * TOTAL_REWARD_PER_MINT;
    }

    function computeFreeMintRewards(uint256 numTokens) public pure returns (RewardsSettings memory) {
        return
            RewardsSettings({
                creatorReward: numTokens * CREATOR_REWARD,
                createReferralReward: numTokens * CREATE_REFERRAL_FREE_MINT_REWARD,
                mintReferralReward: numTokens * MINT_REFERRAL_FREE_MINT_REWARD,
                firstMinterReward: numTokens * FIRST_MINTER_REWARD,
                zoraReward: numTokens * ZORA_FREE_MINT_REWARD
            });
    }

    function computePaidMintRewards(uint256 numTokens) public pure returns (RewardsSettings memory) {
        return
            RewardsSettings({
                creatorReward: 0,
                createReferralReward: numTokens * CREATE_REFERRAL_PAID_MINT_REWARD,
                mintReferralReward: numTokens * MINT_REFERRAL_PAID_MINT_REWARD,
                firstMinterReward: numTokens * FIRST_MINTER_REWARD,
                zoraReward: numTokens * ZORA_PAID_MINT_REWARD
            });
    }

    function depositFreeMintRewards(
        IProtocolRewards protocolRewards,
        address zoraRewardRecipient,
        uint256 totalReward,
        uint256 numTokens,
        address creator,
        address createReferral,
        address mintReferral
    ) external {
        RewardsSettings memory settings = computeFreeMintRewards(numTokens);

        if (createReferral == address(0)) {
            createReferral = zoraRewardRecipient;
        }

        if (mintReferral == address(0)) {
            mintReferral = zoraRewardRecipient;
        }

        protocolRewards.depositRewards{value: totalReward}(
            creator,
            settings.creatorReward,
            createReferral,
            settings.createReferralReward,
            mintReferral,
            settings.mintReferralReward,
            creator,
            settings.firstMinterReward,
            zoraRewardRecipient,
            settings.zoraReward
        );
    }

    function depositPaidMintRewards(
        IProtocolRewards protocolRewards,
        address zoraRewardRecipient,
        uint256 totalReward,
        uint256 numTokens,
        address creator,
        address createReferral,
        address mintReferral
    ) external {
        RewardsSettings memory settings = computePaidMintRewards(numTokens);

        if (createReferral == address(0)) {
            createReferral = zoraRewardRecipient;
        }

        if (mintReferral == address(0)) {
            mintReferral = zoraRewardRecipient;
        }

        protocolRewards.depositRewards{value: totalReward}(
            address(0),
            0,
            createReferral,
            settings.createReferralReward,
            mintReferral,
            settings.mintReferralReward,
            creator,
            settings.firstMinterReward,
            zoraRewardRecipient,
            settings.zoraReward
        );
    }
}

library ERC1155Rewards {
    function handleRewardsAndGetValueSent(
        IProtocolRewards protocolRewards,
        address zoraRewardRecipient,
        uint256 msgValue,
        uint256 numTokens,
        address creator,
        address createReferral,
        address mintReferral
    ) external returns (uint256) {
        uint256 totalReward = RewardSplits.computeTotalReward(numTokens);

        if (msgValue < totalReward) {
            revert RewardSplits.INVALID_ETH_AMOUNT();
        } else if (msgValue == totalReward) {
            RewardSplits.depositFreeMintRewards(protocolRewards, zoraRewardRecipient, totalReward, numTokens, creator, createReferral, mintReferral);

            return 0;
        } else {
            RewardSplits.depositPaidMintRewards(protocolRewards, zoraRewardRecipient, totalReward, numTokens, creator, createReferral, mintReferral);

            unchecked {
                return msgValue - totalReward;
            }
        }
    }
}
