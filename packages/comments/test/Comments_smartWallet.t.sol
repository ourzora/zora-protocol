// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {CommentsTestBase} from "./CommentsTestBase.sol";
import {IMultiOwnable} from "../src/interfaces/IMultiOwnable.sol";
import {IComments} from "../src/interfaces/IComments.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

contract MockMultiOwnable is IMultiOwnable, ERC1155Holder {
    bytes4 internal constant MAGIC_VALUE = bytes4(keccak256("isValidSignature(bytes32,bytes)"));
    mapping(address => bool) public isOwner;

    constructor(address _owner) {
        isOwner[_owner] = true;
    }

    function addOwner(address _owner) external {
        isOwner[_owner] = true;
    }

    function isValidSignature(bytes32 _messageHash, bytes memory _signature) public view returns (bytes4 magicValue) {
        address signatory = ECDSA.recover(_messageHash, _signature);

        if (isOwner[signatory]) {
            return MAGIC_VALUE;
        } else {
            return bytes4(0);
        }
    }

    function isOwnerAddress(address account) external view returns (bool) {
        return isOwner[account];
    }
}

contract Comments_smartWallet is CommentsTestBase {
    function test_commentWithSmartWalletOwner_whenHolder() public {
        address smartWallet = address(new MockMultiOwnable(address(collectorWithoutToken)));

        mock1155.mint(smartWallet, tokenId1, 1, "");

        IComments.CommentIdentifier memory expectedCommentIdentifier = _expectedCommentIdentifier(address(mock1155), tokenId1, collectorWithoutToken);

        vm.expectEmit(true, true, true, true);
        emit IComments.Commented(
            comments.hashCommentIdentifier(expectedCommentIdentifier),
            expectedCommentIdentifier,
            0,
            emptyCommentIdentifier,
            1,
            "test comment",
            block.timestamp,
            address(0)
        );
        vm.prank(collectorWithoutToken);
        vm.deal(collectorWithoutToken, SPARKS_VALUE);
        comments.comment{value: SPARKS_VALUE}({
            commenter: collectorWithoutToken,
            contractAddress: address(mock1155),
            tokenId: tokenId1,
            text: "test comment",
            replyTo: emptyCommentIdentifier,
            commenterSmartWallet: smartWallet,
            referrer: address(0)
        });
    }

    function test_commentWithSmartWalletOwner_whenCreator() public {
        address smartWallet = address(new MockMultiOwnable(address(collectorWithoutToken)));

        uint256 tokenId = 10;
        mock1155.createToken(tokenId, address(smartWallet));

        IComments.CommentIdentifier memory expectedCommentIdentifier = _expectedCommentIdentifier(address(mock1155), tokenId, collectorWithoutToken);

        vm.prank(collectorWithoutToken);
        comments.comment({
            commenter: collectorWithoutToken,
            contractAddress: address(mock1155),
            tokenId: tokenId,
            text: "test comment",
            replyTo: emptyCommentIdentifier,
            commenterSmartWallet: smartWallet,
            referrer: address(0)
        });

        // check that comment was created
        (, bool exists) = comments.hashAndCheckCommentExists(expectedCommentIdentifier);
        assertTrue(exists);
    }

    function test_commentWithSmartWalletOwner_revertsWhenNotHolder() public {
        address smartWallet = address(new MockMultiOwnable(address(collectorWithoutToken)));

        IComments.CommentIdentifier memory emptyReplyTo;

        vm.expectRevert(abi.encodeWithSelector(IComments.NotTokenHolderOrAdmin.selector));
        vm.prank(collectorWithoutToken);
        vm.deal(collectorWithoutToken, SPARKS_VALUE);
        comments.comment{value: SPARKS_VALUE}({
            commenter: collectorWithoutToken,
            contractAddress: address(mock1155),
            tokenId: tokenId1,
            text: "test comment",
            replyTo: emptyReplyTo,
            commenterSmartWallet: smartWallet,
            referrer: address(0)
        });
    }

    function test_commentWithSmartWalletOwner_revertsWhenNotOwner() public {
        address smartWallet = address(new MockMultiOwnable(address(makeAddr("notOwner"))));

        mock1155.mint(smartWallet, tokenId1, 1, "");

        IComments.CommentIdentifier memory emptyReplyTo;

        vm.expectRevert(IComments.NotSmartWalletOwner.selector);
        vm.prank(collectorWithoutToken);
        vm.deal(collectorWithoutToken, SPARKS_VALUE);
        comments.comment{value: SPARKS_VALUE}({
            commenter: collectorWithoutToken,
            contractAddress: address(mock1155),
            tokenId: tokenId1,
            text: "test comment",
            replyTo: emptyReplyTo,
            commenterSmartWallet: smartWallet,
            referrer: address(0)
        });
    }

    function test_commentWithSmartWalletOwner_revertsWhenNotSmartWallet() public {
        address smartWallet = makeAddr("smartWallet");

        mock1155.mint(smartWallet, tokenId1, 1, "");

        IComments.CommentIdentifier memory emptyReplyTo;

        vm.expectRevert(IComments.NotSmartWallet.selector);
        vm.prank(collectorWithoutToken);
        comments.comment({
            commenter: collectorWithoutToken,
            contractAddress: address(mock1155),
            tokenId: tokenId1,
            text: "test comment",
            replyTo: emptyReplyTo,
            commenterSmartWallet: smartWallet,
            referrer: address(0)
        });
    }
}
