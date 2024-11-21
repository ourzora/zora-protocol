// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {CallerAndCommenterImpl} from "../src/utils/CallerAndCommenterImpl.sol";
import {CommentsImpl} from "../src/CommentsImpl.sol";
import {Comments} from "../src/proxy/Comments.sol";
import {IComments} from "../src/interfaces/IComments.sol";
import {Mock1155} from "./mocks/Mock1155.sol";
import {MockZoraTimedSale} from "./mocks/MockZoraTimedSale.sol";
import {MockSecondarySwap} from "./mocks/MockSecondarySwap.sol";
import {ICallerAndCommenter} from "../src/interfaces/ICallerAndCommenter.sol";
import {CallerAndCommenter} from "../src/proxy/CallerAndCommenter.sol";

contract CallerAndCommenterTestBase is Test {
    uint256 constant SPARKS_VALUE = 0.000001 ether;

    address zoraRecipient = makeAddr("zoraRecipient");
    address commentsAdmin = makeAddr("commentsAdmin");
    address commenter;
    uint256 commenterPrivateKey;
    address backfiller = makeAddr("backfiller");
    address tokenAdmin = makeAddr("tokenAdmin");
    address protocolRewards = 0x7777777F279eba3d3Ad8F4E708545291A6fDBA8B;

    IComments.CommentIdentifier emptyCommentIdentifier;

    MockSecondarySwap mockSecondarySwap;

    IComments comments;

    Mock1155 mock1155;

    uint256 tokenId1 = 1;

    MockZoraTimedSale mockMinter;
    ICallerAndCommenter callerAndCommenter;

    function setUp() public {
        vm.createSelectFork("zora_sepolia", 16028863);

        (commenter, commenterPrivateKey) = makeAddrAndKey("commenter");

        mock1155 = new Mock1155();
        mock1155.createToken(tokenId1, tokenAdmin);

        CommentsImpl commentsImpl = new CommentsImpl(SPARKS_VALUE, protocolRewards, zoraRecipient);

        mockMinter = new MockZoraTimedSale();
        mockSecondarySwap = new MockSecondarySwap(mockMinter);

        comments = IComments(payable(address(new Comments(address(commentsImpl)))));

        CallerAndCommenterImpl callerAndCommenterImpl = new CallerAndCommenterImpl(
            address(comments),
            address(mockMinter),
            address(mockSecondarySwap),
            SPARKS_VALUE
        );
        callerAndCommenter = ICallerAndCommenter(payable(address(new CallerAndCommenter(address(callerAndCommenterImpl)))));

        address[] memory delegateCommenters = new address[](1);
        delegateCommenters[0] = address(callerAndCommenter);

        comments.initialize(commentsAdmin, backfiller, delegateCommenters);
        callerAndCommenter.initialize(commentsAdmin);
    }

    function _expectedCommentIdentifier(
        address _commenter,
        address contractAddress,
        uint256 tokenId
    ) internal view returns (IComments.CommentIdentifier memory) {
        return IComments.CommentIdentifier({commenter: _commenter, contractAddress: contractAddress, tokenId: tokenId, nonce: comments.nextNonce()});
    }
}
