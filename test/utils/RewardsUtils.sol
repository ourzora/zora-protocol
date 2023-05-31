// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

contract RewardsUtils {
    uint256 internal constant FREE_MINT_MAX_TOKEN_QUANTITY = 115907997234550746169740725734422330183453438103744308347805389;

    uint256 internal constant TOTAL_REWARD_PER_MINT = 0.000999 ether;
    uint256 internal constant CREATOR_REWARD_FREE_MINT = 0.000555 ether;
    uint256 internal constant FINDER_REWARD_FREE_MINT = 0.000111 ether;
    uint256 internal constant LISTER_REWARD_FREE_MINT = 0.000111 ether;
    uint256 internal constant ZORA_REWARD_FREE_MINT = 0.000222 ether;

    uint256 internal constant FINDER_REWARD_PAID_MINT = 0.000333 ether;
    uint256 internal constant LISTER_REWARD_PAID_MINT = 0.000333 ether;
    uint256 internal constant ZORA_REWARD_PAID_MINT = 0.000333 ether;

    function computeTotalReward(uint256 numTokens) internal pure returns (uint256) {
        return numTokens * TOTAL_REWARD_PER_MINT;
    }

    function computeFreeMintRewards(
        uint256 numTokens
    ) internal pure returns (uint256 totalReward, uint256 creatorReward, uint256 zoraReward, uint256 finderReward, uint256 listerReward) {
        totalReward = numTokens * TOTAL_REWARD_PER_MINT;
        creatorReward = numTokens * CREATOR_REWARD_FREE_MINT;
        zoraReward = numTokens * ZORA_REWARD_FREE_MINT;
        finderReward = numTokens * FINDER_REWARD_FREE_MINT;
        listerReward = numTokens * LISTER_REWARD_FREE_MINT;
    }

    function computePaidMintRewards(
        uint256 numTokens
    ) internal pure returns (uint256 totalReward, uint256 zoraReward, uint256 finderReward, uint256 listerReward) {
        totalReward = numTokens * TOTAL_REWARD_PER_MINT;
        zoraReward = numTokens * ZORA_REWARD_PAID_MINT;
        finderReward = numTokens * FINDER_REWARD_PAID_MINT;
        listerReward = numTokens * LISTER_REWARD_PAID_MINT;
    }
}
