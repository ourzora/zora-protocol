// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import {CommentsImpl} from "../src/CommentsImpl.sol";
import {Comments} from "../src/proxy/Comments.sol";
import {IComments} from "../src/interfaces/IComments.sol";
import {Mock1155} from "./mocks/Mock1155.sol";
import {MockDelegateCommenter} from "./mocks/MockDelegateCommenter.sol";

contract Comments_mintAndCommentTest is Test {
    Mock1155 mock1155;
    CommentsImpl comments;

    uint256 constant SPARKS_VALUE = 0.000001 ether;

    address zoraRecipient = makeAddr("zoraRecipient");
    address commentsAdmin = makeAddr("commentsAdmin");
    address commenter = makeAddr("commenter");
    address tokenAdmin = makeAddr("tokenAdmin");
    address backfiller = makeAddr("backfiller");
    address referrer = makeAddr("referrer");

    uint256 internal constant ZORA_REWARD_PCT = 10;
    uint256 internal constant REFERRER_REWARD_PCT = 20;
    uint256 internal constant BPS_TO_PERCENT_2_DECIMAL_PERCISION = 100;

    uint256 tokenId1 = 1;

    address constant protocolRewards = 0x7777777F279eba3d3Ad8F4E708545291A6fDBA8B;
    MockDelegateCommenter mockDelegateCommenter;

    function setUp() public {
        vm.createSelectFork("zora_sepolia", 14562731);

        CommentsImpl commentsImpl = new CommentsImpl(SPARKS_VALUE, protocolRewards, zoraRecipient);

        comments = CommentsImpl(payable(address(new Comments(address(commentsImpl)))));

        mockDelegateCommenter = new MockDelegateCommenter(address(comments));

        address[] memory delegateCommenters = new address[](1);
        delegateCommenters[0] = address(mockDelegateCommenter);
        comments.initialize({defaultAdmin: commentsAdmin, backfiller: backfiller, delegateCommenters: delegateCommenters});

        mock1155 = new Mock1155();

        mock1155.createToken(tokenId1, tokenAdmin);
    }

    function _expectedCommentIdentifier(
        address _commenter,
        address contractAddress,
        uint256 tokenId
    ) internal view returns (IComments.CommentIdentifier memory) {
        return IComments.CommentIdentifier({commenter: _commenter, contractAddress: contractAddress, tokenId: tokenId, nonce: comments.nextNonce()});
    }

    function testCanDelegateCommentWithSparks() public {
        uint256 quantityToMint = 1;
        uint256 mintFee = 0.000111 ether;

        address contractAddress = address(mock1155);
        uint256 tokenId = tokenId1;

        IComments.CommentIdentifier memory emptyReplyTo;

        IComments.CommentIdentifier memory expectedCommentIdentifier = _expectedCommentIdentifier(commenter, contractAddress, tokenId);

        bytes32 expectedCommentId = comments.hashCommentIdentifier(expectedCommentIdentifier);
        bytes32 expectedReplyToId = bytes32(0);

        vm.deal(commenter, mintFee * quantityToMint + SPARKS_VALUE);
        vm.expectEmit(true, true, true, true);
        emit IComments.Commented(
            expectedCommentId,
            _expectedCommentIdentifier(commenter, contractAddress, tokenId),
            expectedReplyToId,
            emptyReplyTo,
            1,
            "test",
            block.timestamp,
            referrer
        );
        vm.prank(commenter);
        mockDelegateCommenter.mintAndCommentWithSpark{value: SPARKS_VALUE + mintFee * quantityToMint}({
            quantity: quantityToMint,
            collection: address(mock1155),
            tokenId: tokenId1,
            comment: "test",
            referrer: referrer,
            sparksQuantity: 1
        });

        // validate that the protocol creator received rewards
        uint256 zoraReward = (SPARKS_VALUE * (ZORA_REWARD_PCT)) / BPS_TO_PERCENT_2_DECIMAL_PERCISION;
        uint256 referrerReward = (SPARKS_VALUE * (REFERRER_REWARD_PCT)) / BPS_TO_PERCENT_2_DECIMAL_PERCISION;
        vm.assertEq(comments.protocolRewards().balanceOf(zoraRecipient), zoraReward);
        vm.assertEq(comments.protocolRewards().balanceOf(referrer), referrerReward);
        vm.assertEq(comments.protocolRewards().balanceOf(tokenAdmin), SPARKS_VALUE - zoraReward - referrerReward);
    }

    function testDelegateCommentRevertsWhenMoreThanOneSpark() public {
        uint256 quantityToMint = 1;
        uint256 mintFee = 0.000111 ether;

        uint256 sparksQuantity = 2;
        vm.deal(commenter, mintFee * quantityToMint + SPARKS_VALUE * sparksQuantity);

        vm.prank(commenter);
        vm.expectRevert(abi.encodeWithSelector(IComments.IncorrectETHAmountForSparks.selector, SPARKS_VALUE * sparksQuantity, SPARKS_VALUE));
        mockDelegateCommenter.mintAndCommentWithSpark{value: SPARKS_VALUE * sparksQuantity + mintFee * quantityToMint}({
            quantity: quantityToMint,
            collection: address(mock1155),
            tokenId: tokenId1,
            comment: "test",
            referrer: referrer,
            sparksQuantity: sparksQuantity
        });
    }

    function test_delegateComment_nonOwnerCanCommentWithSpark() public {
        address notOwner = makeAddr("notOwner");
        vm.prank(notOwner);

        mockDelegateCommenter.forwardComment(address(mock1155), tokenId1, "test");
    }

    function test_delegateComment_canCommentWithZeroSparks() public {
        // Delegate commenter should be able to comment with 0 spark value
        vm.prank(commenter);
        mockDelegateCommenter.forwardComment(address(mock1155), tokenId1, "test comment with 0 sparks");

        // Verify the comment was created successfully
        IComments.CommentIdentifier memory expectedCommentIdentifier = IComments.CommentIdentifier({
            commenter: commenter,
            contractAddress: address(mock1155),
            tokenId: tokenId1,
            nonce: bytes32(0)
        });

        (, bool exists) = comments.hashAndCheckCommentExists(expectedCommentIdentifier);
        assertTrue(exists, "Comment should exist");
    }
}
