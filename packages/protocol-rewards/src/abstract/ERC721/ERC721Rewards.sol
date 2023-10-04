// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {RewardSplits} from "../RewardSplits.sol";

/// @notice The base logic for handling Zora ERC-721 protocol rewards
/// @dev Used in https://github.com/ourzora/zora-drops-contracts/blob/main/src/ERC721Drop.sol
abstract contract ERC721Rewards is RewardSplits {
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
        uint256 totalReward = computeTotalReward(numTokens);

        if (salePrice == 0) {
            if (msgValue != totalReward) {
                revert INVALID_ETH_AMOUNT();
            }

            _depositFreeMintRewards(totalReward, numTokens, creator, createReferral, mintReferral, firstMinter);
        } else {
            uint256 totalSale = numTokens * salePrice;

            if (msgValue != (totalReward + totalSale)) {
                revert INVALID_ETH_AMOUNT();
            }

            _depositPaidMintRewards(totalReward, numTokens, createReferral, mintReferral, firstMinter);
        }
    }
}
