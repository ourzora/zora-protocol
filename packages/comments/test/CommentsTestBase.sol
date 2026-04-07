// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import {CommentsImpl} from "../src/CommentsImpl.sol";
import {Comments} from "../src/proxy/Comments.sol";
import {IComments} from "../src/interfaces/IComments.sol";
import {Mock1155} from "./mocks/Mock1155.sol";
import {MockCoin} from "./mocks/MockCoin.sol";
import {ProtocolRewards} from "./mocks/ProtocolRewards.sol";

contract CommentsTestBase is Test {
    CommentsImpl internal comments;
    CommentsImpl internal commentsImpl;
    Mock1155 internal mock1155;
    MockCoin internal mockCoin;

    uint256 internal constant SPARKS_VALUE = 0.000001 ether;

    IComments.CommentIdentifier internal emptyCommentIdentifier;
    ProtocolRewards internal protocolRewards;

    address internal commentsAdmin = makeAddr("commentsAdmin");
    address internal commentsBackfiller = makeAddr("commentsBackfiller");
    address internal zoraRecipient = makeAddr("zoraRecipient");
    address internal tokenAdmin;
    uint256 internal tokenAdminPrivateKey;
    address internal collectorWithToken;
    uint256 internal collectorWithTokenPrivateKey;
    address internal collectorWithoutToken = makeAddr("collectorWithoutToken");
    address internal sparker;
    uint256 internal sparkerPrivateKey;

    uint256 internal tokenId0 = 0;
    uint256 internal tokenId1 = 1;
    uint256 internal tokenId2 = 2;

    function setUp() public {
        protocolRewards = new ProtocolRewards();
        commentsImpl = new CommentsImpl(SPARKS_VALUE, address(protocolRewards), zoraRecipient);

        // initialze empty delegateCommenters array
        address[] memory delegateCommenters = new address[](0);

        // intialize proxy
        comments = CommentsImpl(payable(address(new Comments(address(commentsImpl)))));
        comments.initialize({defaultAdmin: commentsAdmin, backfiller: commentsBackfiller, delegateCommenters: delegateCommenters});

        mock1155 = new Mock1155();
        (tokenAdmin, tokenAdminPrivateKey) = makeAddrAndKey("tokenAdmin");

        mock1155.createToken(tokenId1, tokenAdmin);
        mock1155.createToken(tokenId2, tokenAdmin);

        (collectorWithToken, collectorWithTokenPrivateKey) = makeAddrAndKey("collectorWithToken");
        (sparker, sparkerPrivateKey) = makeAddrAndKey("sparker");

        address[] memory owners = new address[](1);
        owners[0] = tokenAdmin;
        mockCoin = new MockCoin(tokenAdmin, owners);
    }

    function _expectedCommentIdentifier(
        address contractAddress,
        uint256 tokenId,
        address commenter
    ) internal view returns (IComments.CommentIdentifier memory) {
        return IComments.CommentIdentifier({commenter: commenter, contractAddress: contractAddress, tokenId: tokenId, nonce: comments.nextNonce()});
    }

    function _mockComment(
        address commenter,
        IComments.CommentIdentifier memory replyTo
    ) internal returns (IComments.CommentIdentifier memory commentIdentifier) {
        vm.startPrank(commenter);
        mock1155.mint(commenter, tokenId1, 1, "");
        vm.stopPrank();

        vm.deal(commenter, SPARKS_VALUE);

        vm.prank(commenter);
        commentIdentifier = comments.comment{value: SPARKS_VALUE}(commenter, address(mock1155), tokenId1, "comment", replyTo, address(0), address(0));
    }
}
