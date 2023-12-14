// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {ERC721} from "./ERC721.sol";
import {ERC1155} from "./ERC1155.sol";

import {ERC721RewardsStorageV1} from "../../src/abstract/ERC721/ERC721RewardsStorageV1.sol";
import {ERC721Rewards} from "../../src/abstract/ERC721/ERC721Rewards.sol";
import {ERC1155Rewards} from "../../src/abstract/ERC1155/ERC1155Rewards.sol";
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

contract MockERC1155 is ERC1155, ERC1155Rewards, ERC1155RewardsStorageV1 {
    error MOCK_ERC1155_INVALID_REMAINING_VALUE();

    address public creator;
    uint256 public salePrice;

    constructor(
        address _creator,
        address _createReferral,
        address _protocolRewards,
        address _zoraRewardRecipient
    ) ERC1155("Mock ERC1155 URI") ERC1155Rewards(_protocolRewards, _zoraRewardRecipient) {
        creator = _creator;
        createReferrals[0] = _createReferral;
    }

    function setSalePrice(uint256 _salePrice) external {
        salePrice = _salePrice;
    }

    function mintWithRewards(address to, uint256 tokenId, uint256 numTokens, address mintReferral) external payable {
        if (firstMinters[tokenId] == address(0)) firstMinters[tokenId] = to;

        uint256 remainingValue = _handleRewardsAndGetValueSent(msg.value, numTokens, creator, createReferrals[tokenId], mintReferral, firstMinters[tokenId]);

        uint256 expectedRemainingValue = salePrice * numTokens;

        if (remainingValue != expectedRemainingValue) revert MOCK_ERC1155_INVALID_REMAINING_VALUE();

        _mint(to, tokenId, numTokens, "");
    }
}
