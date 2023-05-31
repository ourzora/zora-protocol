// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

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

    error INVALID_TOKEN_QUANTITY();
    error INSUFFICIENT_ETH();
}
