// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {RewardSplits, RewardSplitsLib} from "../RewardSplits.sol";

/// @notice The base logic for handling Zora ERC-721 protocol rewards
/// @dev Used in https://github.com/ourzora/zora-drops-contracts/blob/main/src/ERC721Drop.sol
abstract contract ERC721Rewards is RewardSplits {
    uint256 internal constant TOTAL_REWARD_PER_MINT_LEGACY = 0.000777 ether;

    constructor(address _protocolRewards, address _zoraRewardRecipient) payable RewardSplits(_protocolRewards, _zoraRewardRecipient) {}

    function _handleRewards(
        uint256 msgValue,
        uint256 numTokens,
        uint256 salePrice,
        address creator,
        address createReferral,
        address mintReferral,
        address firstMinter
    ) internal {
        uint256 totalReward = computeTotalReward(TOTAL_REWARD_PER_MINT_LEGACY, numTokens);

        RewardsSettings memory settings;

        if (salePrice == 0) {
            if (msgValue != totalReward) {
                revert INVALID_ETH_AMOUNT();
            }
            settings = RewardSplitsLib.getRewards(false, totalReward);
        } else {
            uint256 totalSale = numTokens * salePrice;

            if (msgValue != (totalReward + totalSale)) {
                revert INVALID_ETH_AMOUNT();
            }

            settings = RewardSplitsLib.getRewards(true, totalReward);
        }

        protocolRewards.depositRewards{value: totalReward}(
            // if there was no creator reward amount, 0 out that address
            settings.creatorReward == 0 ? address(0) : creator,
            settings.creatorReward,
            createReferral == address(0) ? zoraRewardRecipient : createReferral,
            settings.createReferralReward,
            mintReferral == address(0) ? zoraRewardRecipient : mintReferral,
            settings.mintReferralReward,
            firstMinter,
            settings.firstMinterReward,
            zoraRewardRecipient,
            settings.zoraReward
        );
    }
}
