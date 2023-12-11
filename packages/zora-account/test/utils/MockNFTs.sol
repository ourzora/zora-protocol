// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {ERC721} from "./ERC721.sol";
import {ERC1155} from "./ERC1155.sol";

contract MockERC721 is ERC721 {
    address public creator;
    uint256 public salePrice;
    uint256 public currentTokenId;

    constructor(address _creator) ERC721("Mock ERC721", "MOCK") {
        creator = _creator;
    }

    function setSalePrice(uint256 _salePrice) external {
        require(msg.sender == creator, "MockERC721: only creator can set sale price");

        salePrice = _salePrice;
    }

    function mintWithRewards(address to, uint256 numTokens) external payable {
        require(msg.value == (salePrice * numTokens), "MockERC721: incorrect value sent");

        for (uint256 i; i < numTokens; ++i) {
            _mint(to, currentTokenId++);
        }
    }
}

contract MockERC1155 is ERC1155 {
    address public creator;
    uint256 public salePrice;

    constructor(address _creator) ERC1155("Mock ERC1155 URI") {
        creator = _creator;
    }

    function setSalePrice(uint256 _salePrice) external {
        require(msg.sender == creator, "MockERC1155: only creator can set sale price");

        salePrice = _salePrice;
    }

    function mintWithRewards(address to, uint256 tokenId, uint256 numTokens) external payable {
        require(msg.value == (salePrice * numTokens), "MockERC1155: incorrect value sent");

        _mint(to, tokenId, numTokens, "");
    }
}
