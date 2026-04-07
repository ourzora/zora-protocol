// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract MockMintableERC721 is ERC721 {
    constructor() ERC721("", "") {}
    function mint(uint256 tokenId) external {
        _mint(msg.sender, tokenId);
    }
}
