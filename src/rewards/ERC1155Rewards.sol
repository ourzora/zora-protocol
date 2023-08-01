// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {RewardSplits} from "@zoralabs/protocol-rewards/dist/contracts/abstract/RewardSplits.sol";

contract ERC1155RewardsStorage {
    mapping(uint256 => address) public createReferrals;
}

abstract contract ERC1155Rewards is RewardSplits {
    constructor(address _protocolRewards, address _zoraRewardRecipient) payable RewardSplits(_protocolRewards, _zoraRewardRecipient) {}

    function _handleRewardsAndGetValueSent(
        uint256 msgValue,
        uint256 numTokens,
        address creator,
        address mintReferral,
        address createReferral
    ) internal returns (uint256) {
        if (creator == address(0)) {
            revert CREATOR_FUNDS_RECIPIENT_NOT_SET();
        }

        uint256 totalReward = computeTotalReward(numTokens);

        if (msgValue < totalReward) {
            revert INVALID_ETH_AMOUNT();
        } else if (msgValue == totalReward) {
            _depositFreeMintRewards(totalReward, numTokens, creator, mintReferral, createReferral);

            return 0;
        } else {
            _depositPaidMintRewards(totalReward, numTokens, creator, mintReferral, createReferral);

            unchecked {
                return msgValue - totalReward;
            }
        }
    }
}
