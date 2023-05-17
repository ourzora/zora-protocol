// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IRewardsManager} from "./RewardsManager.sol";

interface ICreatorRewards {
    event FreeMintRewardsTransferred(
        address indexed creator,
        uint256 creatorReward,
        address indexed finder,
        uint256 finderReward,
        address indexed lister,
        uint256 listerReward
    );
    event PaidMintRewardsTransferred(address indexed finder, uint256 finderReward, address indexed lister, uint256 listerReward);

    error INSUFFICIENT_ETH();
}

abstract contract CreatorRewards is ICreatorRewards {
    uint256 internal constant TOTAL_REWARD_PER_MINT = 0.000999 ether;

    uint256 internal constant CREATOR_REWARD_FREE_MINT = 0.000555 ether;
    uint256 internal constant FINDER_REWARD_FREE_MINT = 0.000111 ether;
    uint256 internal constant LISTER_REWARD_FREE_MINT = 0.000111 ether;
    uint256 internal constant ZORA_REWARD_FREE_MINT = 0.000222 ether;

    uint256 internal constant FINDER_REWARD_PAID_MINT = 0.000333 ether;
    uint256 internal constant LISTER_REWARD_PAID_MINT = 0.000333 ether;
    uint256 internal constant ZORA_REWARD_PAID_MINT = 0.000333 ether;

    address internal immutable ZORA_REWARD_RECIPIENT;

    IRewardsManager internal immutable REWARDS_MANAGER;

    constructor(address _rewardsManager, address _zoraRewardRecipient) {
        REWARDS_MANAGER = IRewardsManager(_rewardsManager);
        ZORA_REWARD_RECIPIENT = _zoraRewardRecipient;
    }

    function _parseAttachedEth(uint256 msgValue, uint256 numTokens) internal pure returns (uint256) {
        uint256 minEthRequired = numTokens * TOTAL_REWARD_PER_MINT;

        if (msgValue < minEthRequired) {
            revert INSUFFICIENT_ETH();
        } else if (msgValue == minEthRequired) {
            return 0;
        } else {
            unchecked {
                return msgValue - minEthRequired;
            }
        }
    }

    function _transferFreeMintRewards(uint256 numTokens, address creator, address finder, address lister) internal {
        uint256 creatorReward = numTokens * CREATOR_REWARD_FREE_MINT;
        uint256 zoraReward = numTokens * ZORA_REWARD_FREE_MINT;
        uint256 finderReward = numTokens * FINDER_REWARD_FREE_MINT;
        uint256 listerReward = numTokens * LISTER_REWARD_FREE_MINT;

        uint256 totalReward = creatorReward + zoraReward + finderReward + listerReward;

        if (finder == address(0)) {
            finder = ZORA_REWARD_RECIPIENT;
        }

        if (lister == address(0)) {
            lister = ZORA_REWARD_RECIPIENT;
        }

        REWARDS_MANAGER.addReward{value: totalReward}(creator, creatorReward, ZORA_REWARD_RECIPIENT, zoraReward, finder, finderReward, lister, listerReward);

        emit FreeMintRewardsTransferred(creator, creatorReward, finder, finderReward, lister, listerReward);
    }

    function _transferPaidMintRewards(uint256 msgValue, uint256 numTokens, address finder, address lister) internal returns (uint256 remainingEth) {
        uint256 zoraReward = numTokens * ZORA_REWARD_PAID_MINT;
        uint256 finderReward = numTokens * FINDER_REWARD_PAID_MINT;
        uint256 listerReward = numTokens * LISTER_REWARD_PAID_MINT;

        uint256 totalReward = zoraReward + finderReward + listerReward;

        remainingEth = msgValue - totalReward;

        if (finder == address(0)) {
            finder = ZORA_REWARD_RECIPIENT;
        }

        if (lister == address(0)) {
            lister = ZORA_REWARD_RECIPIENT;
        }

        REWARDS_MANAGER.addReward{value: totalReward}(ZORA_REWARD_RECIPIENT, zoraReward, finder, finderReward, lister, listerReward);

        emit PaidMintRewardsTransferred(finder, finderReward, lister, listerReward);
    }
}
