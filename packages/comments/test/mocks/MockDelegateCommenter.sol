// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IComments} from "../../src/interfaces/IComments.sol";
import {Mock1155} from "./Mock1155.sol";

contract MockDelegateCommenter {
    IComments immutable comments;
    uint256 MINT_FEE = 0.000111 ether;
    uint256 constant SPARKS_VALUE = 0.000001 ether;

    constructor(address _comments) {
        comments = IComments(_comments);
    }

    IComments.CommentIdentifier emptyCommentIdentifier;

    function forwardComment(address collection, uint256 tokenId, string calldata comment) external {
        comments.delegateComment(msg.sender, collection, tokenId, comment, emptyCommentIdentifier, address(0), address(0));
    }

    function mintAndCommentWithSpark(
        uint256 quantity,
        address collection,
        uint256 tokenId,
        string calldata comment,
        address referrer,
        uint256 sparksQuantity
    ) external payable {
        require(msg.value == SPARKS_VALUE * sparksQuantity + MINT_FEE * quantity, "Invalid value");
        Mock1155(collection).mint(msg.sender, tokenId, quantity, "");

        // get sparks value to send to comments contract
        comments.delegateComment{value: SPARKS_VALUE * sparksQuantity}(msg.sender, collection, tokenId, comment, emptyCommentIdentifier, address(0), referrer);
    }
}
