// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IProtocolRewards} from "../interfaces/IProtocolRewards.sol";

struct RewardsSettings {
    uint256 creatorReward;
    uint256 createReferralReward;
    uint256 mintReferralReward;
    uint256 firstMinterReward;
    uint256 zoraReward;
}

/// @notice Common logic for between Zora ERC-721 & ERC-1155 contracts for protocol reward splits & deposits
abstract contract RewardSplits {
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

    address internal immutable zoraRewardRecipient;
    IProtocolRewards internal immutable protocolRewards;

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

    function _depositFreeMintRewards(
        uint256 totalReward,
        uint256 numTokens,
        address creator,
        address createReferral,
        address mintReferral,
        address firstMinter
    ) internal {
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
            firstMinter,
            settings.firstMinterReward,
            zoraRewardRecipient,
            settings.zoraReward
        );
    }

    function _depositPaidMintRewards(uint256 totalReward, uint256 numTokens, address createReferral, address mintReferral, address firstMinter) internal {
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
            firstMinter,
            settings.firstMinterReward,
            zoraRewardRecipient,
            settings.zoraReward
        );
    }
}
