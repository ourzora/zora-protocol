// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IRewardsManager} from "./RewardsManager.sol";
import {ICreatorRewards} from "../interfaces/ICreatorRewards.sol";

abstract contract CreatorRewards is ICreatorRewards {
    bytes4 public constant ZORA_FREE_MINT_REWARD_TYPE = bytes4(keccak256("ZORA_FREE_MINT_REWARDS"));
    bytes4 public constant ZORA_PAID_MINT_REWARD_TYPE = bytes4(keccak256("ZORA_PAID_MINT_REWARDS"));

    uint256 internal constant TOTAL_REWARD_PER_MINT = 0.000999 ether;
    uint256 internal constant MAX_TOKEN_QUANTITY = 115907997234550746169740725734422330183453438103744308347805389;

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

    function _handleMintInput(uint256 msgValue, uint256 numTokens) internal pure returns (bool) {
        if (numTokens > MAX_TOKEN_QUANTITY) {
            revert INVALID_TOKEN_QUANTITY();
        }

        uint256 minEthRequired = numTokens * TOTAL_REWARD_PER_MINT;

        if (msgValue < minEthRequired) {
            revert INSUFFICIENT_ETH();
        } else if (msgValue == minEthRequired) {
            return true;
        } else {
            return false;
        }
    }

    function _transferFreeMintRewards(uint256 numTokens, address creator, address finder, address lister) internal {
        (uint256 totalReward, uint256 creatorReward, uint256 zoraReward, uint256 finderReward, uint256 listerReward) = _computeFreeMintRewards(numTokens);

        if (finder == address(0)) {
            finder = ZORA_REWARD_RECIPIENT;
        }

        if (lister == address(0)) {
            lister = ZORA_REWARD_RECIPIENT;
        }

        REWARDS_MANAGER.addReward{value: totalReward}(
            ZORA_FREE_MINT_REWARD_TYPE,
            creator,
            creatorReward,
            ZORA_REWARD_RECIPIENT,
            zoraReward,
            finder,
            finderReward,
            lister,
            listerReward
        );

        emit FreeMintRewardsTransferred(creator, creatorReward, finder, finderReward, lister, listerReward);
    }

    function _transferPaidMintRewards(uint256 msgValue, uint256 numTokens, address finder, address lister) internal returns (uint256 remainingEth) {
        (uint256 totalReward, uint256 zoraReward, uint256 finderReward, uint256 listerReward) = _computePaidMintRewards(numTokens);

        remainingEth = msgValue - totalReward;

        if (finder == address(0)) {
            finder = ZORA_REWARD_RECIPIENT;
        }

        if (lister == address(0)) {
            lister = ZORA_REWARD_RECIPIENT;
        }

        REWARDS_MANAGER.addReward{value: totalReward}(
            ZORA_PAID_MINT_REWARD_TYPE,
            ZORA_REWARD_RECIPIENT,
            zoraReward,
            finder,
            finderReward,
            lister,
            listerReward
        );

        emit PaidMintRewardsTransferred(finder, finderReward, lister, listerReward);
    }

    function _computeFreeMintRewards(
        uint256 numTokens
    ) private pure returns (uint256 totalReward, uint256 creatorReward, uint256 zoraReward, uint256 finderReward, uint256 listerReward) {
        totalReward = numTokens * TOTAL_REWARD_PER_MINT;
        creatorReward = numTokens * CREATOR_REWARD_FREE_MINT;
        zoraReward = numTokens * ZORA_REWARD_FREE_MINT;
        finderReward = numTokens * FINDER_REWARD_FREE_MINT;
        listerReward = numTokens * LISTER_REWARD_FREE_MINT;
    }

    function _computePaidMintRewards(
        uint256 numTokens
    ) private pure returns (uint256 totalReward, uint256 zoraReward, uint256 finderReward, uint256 listerReward) {
        totalReward = numTokens * TOTAL_REWARD_PER_MINT;
        zoraReward = numTokens * ZORA_REWARD_PAID_MINT;
        finderReward = numTokens * FINDER_REWARD_PAID_MINT;
        listerReward = numTokens * LISTER_REWARD_PAID_MINT;
    }
}
