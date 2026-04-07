// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {ERC721} from "./ERC721.sol";
import {ERC1155} from "./ERC1155.sol";

import {ERC721RewardsStorageV1} from "../../src/abstract/ERC721/ERC721RewardsStorageV1.sol";
import {ERC721Rewards} from "../../src/abstract/ERC721/ERC721Rewards.sol";
import {RewardSplits, RewardSplitsLib} from "../../src/abstract/RewardSplits.sol";
import {ERC1155RewardsStorageV1} from "../../src/abstract/ERC1155/ERC1155RewardsStorageV1.sol";

contract MockERC721 is ERC721, ERC721Rewards, ERC721RewardsStorageV1 {
    address public creator;
    uint256 public salePrice;
    uint256 public currentTokenId;

    constructor(
        address _creator,
        address _createReferral,
        address _protocolRewards,
        address _zoraRewardRecipient
    ) ERC721("Mock ERC721", "MOCK") ERC721Rewards(_protocolRewards, _zoraRewardRecipient) {
        creator = _creator;
        createReferral = _createReferral;
    }

    function setSalePrice(uint256 _salePrice) external {
        salePrice = _salePrice;
    }

    function mintWithRewards(address to, uint256 numTokens, address mintReferral) external payable {
        if (firstMinter == address(0)) firstMinter = to;

        _handleRewards(msg.value, numTokens, salePrice, creator != address(0) ? creator : address(this), createReferral, mintReferral, firstMinter);

        for (uint256 i; i < numTokens; ++i) {
            _mint(to, currentTokenId++);
        }
    }
}

contract MockERC1155 is ERC1155, RewardSplits, ERC1155RewardsStorageV1 {
    error MOCK_ERC1155_INVALID_REMAINING_VALUE();

    address public creator;
    uint256 public salePrice;

    constructor(
        address _creator,
        address _createReferral,
        address _protocolRewards,
        address _zoraRewardRecipient
    ) ERC1155("Mock ERC1155 URI") RewardSplits(_protocolRewards, _zoraRewardRecipient) {
        creator = _creator;
        createReferrals[0] = _createReferral;
    }

    function setSalePrice(uint256 _salePrice) external {
        salePrice = _salePrice;
    }

    function mintWithRewards(address to, uint256 tokenId, uint256 numTokens, address mintReferral, uint256 rewardValue) external payable {
        if (firstMinters[tokenId] == address(0)) firstMinters[tokenId] = to;

        uint256 totalReward = computeTotalReward(rewardValue, numTokens);

        uint256 remainingValue = _handleRewardsAndGetValueRemaining(msg.value, totalReward, tokenId, mintReferral);

        uint256 expectedRemainingValue = salePrice * numTokens;

        if (remainingValue != expectedRemainingValue) revert MOCK_ERC1155_INVALID_REMAINING_VALUE();

        _mint(to, tokenId, numTokens, "");
    }

    function _handleRewardsAndGetValueRemaining(
        uint256 totalSentValue,
        uint256 totalReward,
        uint256 tokenId,
        address mintReferral
    ) internal returns (uint256 valueRemaining) {
        // 1. Get rewards recipients

        // create referral is pulled from storage, if it's not set, defaults to zora reward recipient
        address createReferral = createReferrals[tokenId];
        if (createReferral == address(0)) {
            createReferral = zoraRewardRecipient;
        }

        // mint referral is passed in arguments to minting functions; if it's not set, defaults to zora reward recipient
        if (mintReferral == address(0)) {
            mintReferral = zoraRewardRecipient;
        }

        // creator reward recipient is pulled from storage, if it's not set, defaults to zora reward recipient
        address creatorRewardRecipient = creator;
        if (creatorRewardRecipient == address(0)) {
            creatorRewardRecipient = zoraRewardRecipient;
        }

        // first minter is pulled from storage, if it's not set, defaults to creator reward recipient (which is zora if there is no creator reward recipient set)
        address firstMinter = firstMinters[tokenId];
        if (firstMinter == address(0)) {
            firstMinter = creatorRewardRecipient;
        }

        // 2. Get rewards amounts - which varies if its a paid or free mint

        RewardsSettings memory settings;
        if (totalSentValue < totalReward) {
            revert INVALID_ETH_AMOUNT();
            // if value sent is the same as the reward amount, we assume its a free mint
        } else if (totalSentValue == totalReward) {
            settings = RewardSplitsLib.getRewards(false, totalReward);
            // otherwise, we assume its a paid mint
        } else {
            settings = RewardSplitsLib.getRewards(true, totalReward);

            unchecked {
                valueRemaining = totalSentValue - totalReward;
            }
        }

        // 3. Deposit rewards rewards

        protocolRewards.depositRewards{value: totalReward}(
            // if there was no creator reward amount, 0 out that address
            settings.creatorReward == 0 ? address(0) : creatorRewardRecipient,
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
}
