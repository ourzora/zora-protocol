// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IProtocolRewards} from "../interfaces/IProtocolRewards.sol";

struct RewardsSettings {
    uint256 creatorReward;
    uint256 createReferralReward;
    uint256 mintReferralReward;
    uint256 firstMinterReward;
    uint256 zoraReward;
    uint256 platformReferralReward;
}

/// @notice Common logic for between Zora ERC-721 & ERC-1155 contracts for protocol reward splits & deposits
abstract contract RewardSplits {
    error CREATOR_FUNDS_RECIPIENT_NOT_SET();
    error INVALID_ADDRESS_ZERO();
    error INVALID_ETH_AMOUNT();
    error ONLY_CREATE_REFERRAL();

    bytes4 public constant PLATFORM_REFERRAL_REWARD_DEPOSIT_REASON = bytes4(keccak256("PLATFORM_REFERRAL_REWARD"));

    uint256 internal constant TOTAL_REWARD_PER_MINT = 0.00111 ether;
    uint256 internal constant CREATOR_REWARD_SPLIT = 0.000555 ether;
    uint256 internal constant NON_CREATOR_REWARDS_SPLIT = 0.000111 ether;

    address internal immutable zoraRewardRecipient;
    IProtocolRewards public immutable protocolRewards;

    constructor(address _protocolRewards, address _zoraRewardRecipient) payable {
        if (_protocolRewards == address(0) || _zoraRewardRecipient == address(0)) {
            revert INVALID_ADDRESS_ZERO();
        }

        protocolRewards = IProtocolRewards(_protocolRewards);
        zoraRewardRecipient = _zoraRewardRecipient;
    }

    function computeTotalReward(uint256 numTokens) public pure returns (uint256) {
        return numTokens * TOTAL_REWARD_PER_MINT;
    }

    function computeFreeMintRewards(uint256 numTokens) public pure returns (RewardsSettings memory) {
        return
            RewardsSettings({
                creatorReward: numTokens * CREATOR_REWARD_SPLIT,
                createReferralReward: numTokens * NON_CREATOR_REWARDS_SPLIT,
                mintReferralReward: numTokens * NON_CREATOR_REWARDS_SPLIT,
                firstMinterReward: numTokens * NON_CREATOR_REWARDS_SPLIT,
                zoraReward: numTokens * NON_CREATOR_REWARDS_SPLIT,
                platformReferralReward: numTokens * NON_CREATOR_REWARDS_SPLIT
            });
    }

    function computePaidMintRewards(uint256 numTokens) public pure returns (RewardsSettings memory) {
        return
            RewardsSettings({
                creatorReward: 0,
                createReferralReward: numTokens * NON_CREATOR_REWARDS_SPLIT,
                mintReferralReward: numTokens * NON_CREATOR_REWARDS_SPLIT,
                firstMinterReward: numTokens * NON_CREATOR_REWARDS_SPLIT,
                zoraReward: numTokens * (NON_CREATOR_REWARDS_SPLIT + CREATOR_REWARD_SPLIT),
                platformReferralReward: numTokens * NON_CREATOR_REWARDS_SPLIT
            });
    }

    function _depositFreeMintRewards(
        uint256 totalReward,
        uint256 numTokens,
        address creator,
        address createReferral,
        address mintReferral,
        address firstMinter,
        address platformReferral
    ) internal {
        RewardsSettings memory settings = computeFreeMintRewards(numTokens);

        if (createReferral == address(0)) {
            createReferral = zoraRewardRecipient;
        }

        if (mintReferral == address(0)) {
            mintReferral = zoraRewardRecipient;
        }

        if (platformReferral == address(0)) {
            platformReferral = zoraRewardRecipient;
        }

        protocolRewards.depositRewards{value: totalReward - settings.platformReferralReward}(
            creator,
            settings.creatorReward,
            createReferral,
            settings.createReferralReward,
            mintReferral,
            settings.mintReferralReward,
            firstMinter,
            settings.firstMinterReward,
            zoraRewardRecipient,
            settings.zoraReward
        );

        protocolRewards.deposit{value: settings.platformReferralReward}(platformReferral, PLATFORM_REFERRAL_REWARD_DEPOSIT_REASON, "");
    }

    function _depositPaidMintRewards(
        uint256 totalReward,
        uint256 numTokens,
        address createReferral,
        address mintReferral,
        address firstMinter,
        address platformReferral
    ) internal {
        RewardsSettings memory settings = computePaidMintRewards(numTokens);

        if (createReferral == address(0)) {
            createReferral = zoraRewardRecipient;
        }

        if (mintReferral == address(0)) {
            mintReferral = zoraRewardRecipient;
        }

        if (platformReferral == address(0)) {
            platformReferral = zoraRewardRecipient;
        }

        protocolRewards.depositRewards{value: totalReward - settings.platformReferralReward}(
            address(0),
            0,
            createReferral,
            settings.createReferralReward,
            mintReferral,
            settings.mintReferralReward,
            firstMinter,
            settings.firstMinterReward,
            zoraRewardRecipient,
            settings.zoraReward
        );

        protocolRewards.deposit{value: settings.platformReferralReward}(platformReferral, PLATFORM_REFERRAL_REWARD_DEPOSIT_REASON, "");
    }
}
