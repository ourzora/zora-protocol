// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {RewardSplits} from "../RewardSplits.sol";

/// @notice The base logic for handling Zora ERC-1155 protocol rewards
/// @dev Used in https://github.com/ourzora/zora-1155-contracts/blob/main/src/nft/ZoraCreator1155Impl.sol
abstract contract ERC1155Rewards is RewardSplits {
    constructor(address _protocolRewards, address _zoraRewardRecipient) payable RewardSplits(_protocolRewards, _zoraRewardRecipient) {}

    function _handleRewardsAndGetValueSent(
        uint256 msgValue,
        uint256 numTokens,
        address creator,
        address createReferral,
        address mintReferral,
        address firstMinter
    ) internal returns (uint256) {
        uint256 totalReward = computeTotalReward(numTokens);

        // If we have no first minter, first minter should be the creator.
        if (firstMinter == address(0)) {
            firstMinter = creator;
        }

        if (msgValue < totalReward) {
            revert INVALID_ETH_AMOUNT();
        } else if (msgValue == totalReward) {
            _depositFreeMintRewards(totalReward, numTokens, creator, createReferral, mintReferral, firstMinter);

            return 0;
        } else {
            _depositPaidMintRewards(totalReward, numTokens, createReferral, mintReferral, firstMinter);

            unchecked {
                return msgValue - totalReward;
            }
        }
    }
}
