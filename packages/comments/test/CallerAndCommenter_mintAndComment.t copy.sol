// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IComments} from "../src/interfaces/IComments.sol";
import {ICallerAndCommenter} from "../src/interfaces/ICallerAndCommenter.sol";
import {CallerAndCommenterTestBase} from "./CallerAndCommenterTestBase.sol";

contract CallerAndCommenterMintAndCommentTest is CallerAndCommenterTestBase {
    function testCanTimedSaleMintAndComment() public {
        uint256 quantityToMint = 1;
        uint256 mintFee = 0.000111 ether;

        address contractAddress = address(mock1155);
        uint256 tokenId = tokenId1;

        IComments.CommentIdentifier memory expectedCommentIdentifier = _expectedCommentIdentifier(commenter, contractAddress, tokenId);

        bytes32 expectedCommentId = comments.hashCommentIdentifier(expectedCommentIdentifier);
        bytes32 expectedReplyToId = bytes32(0);

        uint64 sparksQuantity = 0;

        address mintReferral = address(0);

        vm.deal(commenter, mintFee * quantityToMint);
        vm.expectEmit(true, true, true, true);
        emit IComments.Commented(
            expectedCommentId,
            expectedCommentIdentifier,
            expectedReplyToId,
            emptyCommentIdentifier,
            sparksQuantity,
            "test",
            block.timestamp,
            address(0)
        );
        vm.expectEmit(true, true, true, true);
        emit ICallerAndCommenter.MintedAndCommented(expectedCommentId, expectedCommentIdentifier, quantityToMint, "test");
        vm.prank(commenter);
        callerAndCommenter.timedSaleMintAndComment{value: mintFee * quantityToMint}(
            commenter,
            quantityToMint,
            address(mock1155),
            tokenId1,
            mintReferral,
            "test"
        );

        // validate that the comment was created
        (, bool exists) = comments.hashAndCheckCommentExists(expectedCommentIdentifier);
        assertEq(exists, true);
        // make sure mock 1155 got the full mint fee
        assertEq(address(mock1155).balance, mintFee * quantityToMint);
    }

    function testWhenNoCommentDoesNotComment() public {
        uint256 quantityToMint = 1;
        uint256 mintFee = 0.000111 ether;

        vm.deal(commenter, mintFee * quantityToMint);
        vm.prank(commenter);
        IComments.CommentIdentifier memory result = callerAndCommenter.timedSaleMintAndComment{value: mintFee * quantityToMint}(
            commenter,
            quantityToMint,
            address(mock1155),
            tokenId1,
            address(0),
            ""
        );

        assertEq(result.commenter, address(0));
        assertEq(result.contractAddress, address(0));
        assertEq(result.tokenId, 0);
        assertEq(result.nonce, bytes32(0));
    }

    function testPermitTimedSaleMintAndComment() public {
        uint256 quantityToMint = 1;
        uint256 mintFee = 0.000111 ether;

        address contractAddress = address(mock1155);
        uint256 tokenId = tokenId1;

        string memory comment = "test comment";

        ICallerAndCommenter.PermitTimedSaleMintAndComment memory permit = _createPermit(
            commenter,
            quantityToMint,
            contractAddress,
            tokenId,
            address(0),
            comment,
            block.timestamp + 1 hours
        );

        bytes memory signature = _signPermit(permit, commenterPrivateKey);

        IComments.CommentIdentifier memory expectedCommentIdentifier = _expectedCommentIdentifier(commenter, contractAddress, tokenId);

        bytes32 expectedCommentId = comments.hashCommentIdentifier(expectedCommentIdentifier);

        vm.deal(commenter, mintFee * quantityToMint);
        vm.expectEmit(true, true, true, true);
        emit IComments.Commented(expectedCommentId, expectedCommentIdentifier, bytes32(0), emptyCommentIdentifier, 0, comment, block.timestamp, address(0));
        vm.expectEmit(true, true, true, true);
        emit ICallerAndCommenter.MintedAndCommented(expectedCommentId, expectedCommentIdentifier, quantityToMint, comment);
        IComments.CommentIdentifier memory result = callerAndCommenter.permitTimedSaleMintAndComment{value: mintFee * quantityToMint}(permit, signature);

        assertEq(result.commenter, commenter);
        assertEq(result.contractAddress, contractAddress);
        assertEq(result.tokenId, tokenId);
        assertEq(result.nonce, bytes32(0));

        // validate that the comment was created
        (, bool exists) = comments.hashAndCheckCommentExists(expectedCommentIdentifier);
        assertEq(exists, true);
        // make sure mock 1155 got the full mint fee
        assertEq(address(mock1155).balance, mintFee * quantityToMint);
    }

    function testPermitTimedSaleMintAndComment_ExpiredDeadline() public {
        uint256 quantityToMint = 1;
        uint256 mintFee = 0.000111 ether;

        ICallerAndCommenter.PermitTimedSaleMintAndComment memory permit = _createPermit(
            commenter,
            quantityToMint,
            address(mock1155),
            tokenId1,
            address(0),
            "test comment",
            block.timestamp - 1 // Expired deadline
        );

        bytes memory signature = _signPermit(permit, commenterPrivateKey);

        vm.deal(commenter, mintFee * quantityToMint);
        vm.expectRevert(abi.encodeWithSelector(IComments.ERC2612ExpiredSignature.selector, permit.deadline));
        callerAndCommenter.permitTimedSaleMintAndComment{value: mintFee * quantityToMint}(permit, signature);
    }

    function testPermitTimedSaleMintAndComment_InvalidSignature() public {
        uint256 quantityToMint = 1;
        uint256 mintFee = 0.000111 ether;

        ICallerAndCommenter.PermitTimedSaleMintAndComment memory permit = _createPermit(
            commenter,
            quantityToMint,
            address(mock1155),
            tokenId1,
            address(0),
            "test comment",
            block.timestamp + 1 hours
        );

        bytes memory signature = _signPermit(permit, 5); // Wrong signer

        vm.deal(commenter, mintFee * quantityToMint);
        vm.expectRevert(IComments.InvalidSignature.selector);
        callerAndCommenter.permitTimedSaleMintAndComment{value: mintFee * quantityToMint}(permit, signature);
    }

    function testPermitTimedSaleMintAndComment_IncorrectDestinationChain() public {
        uint256 quantityToMint = 1;
        uint256 mintFee = 0.000111 ether;

        ICallerAndCommenter.PermitTimedSaleMintAndComment memory permit = _createPermit(
            commenter,
            quantityToMint,
            address(mock1155),
            tokenId1,
            address(0),
            "test comment",
            block.timestamp + 1 hours
        );
        permit.destinationChainId = uint32(block.chainid) + 1; // Incorrect destination chain

        bytes memory signature = _signPermit(permit, commenterPrivateKey);

        vm.deal(commenter, mintFee * quantityToMint);
        vm.expectRevert(abi.encodeWithSelector(ICallerAndCommenter.IncorrectDestinationChain.selector, permit.destinationChainId));
        callerAndCommenter.permitTimedSaleMintAndComment{value: mintFee * quantityToMint}(permit, signature);
    }

    function _createPermit(
        address _commenter,
        uint256 _quantity,
        address _collection,
        uint256 _tokenId,
        address _mintReferral,
        string memory _comment,
        uint256 _deadline
    ) internal view returns (ICallerAndCommenter.PermitTimedSaleMintAndComment memory) {
        return
            ICallerAndCommenter.PermitTimedSaleMintAndComment({
                commenter: _commenter,
                quantity: _quantity,
                collection: _collection,
                tokenId: _tokenId,
                mintReferral: _mintReferral,
                comment: _comment,
                deadline: _deadline,
                nonce: bytes32(0),
                sourceChainId: uint32(block.chainid),
                destinationChainId: uint32(block.chainid)
            });
    }

    function _signPermit(ICallerAndCommenter.PermitTimedSaleMintAndComment memory _permit, uint256 _privateKey) internal view returns (bytes memory) {
        bytes32 digest = callerAndCommenter.hashPermitTimedSaleMintAndComment(_permit);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_privateKey, digest);
        return abi.encodePacked(r, s, v);
    }
}
