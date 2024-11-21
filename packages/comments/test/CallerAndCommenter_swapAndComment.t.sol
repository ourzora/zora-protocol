// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IComments} from "../src/interfaces/IComments.sol";
import {ICallerAndCommenter} from "../src/interfaces/ICallerAndCommenter.sol";
import {CallerAndCommenterTestBase} from "./CallerAndCommenterTestBase.sol";
import {ISecondarySwap} from "../src/interfaces/ISecondarySwap.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {CallerAndCommenterImpl} from "../src/utils/CallerAndCommenterImpl.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IERC1155} from "@openzeppelin/contracts/interfaces/IERC1155.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";

contract CallerAndCommenterSwapAndCommentTest is CallerAndCommenterTestBase {
    function testBuyOnSecondaryAndComment() public {
        // setup the sale so that we have a link between the erc20z and the 1155
        address erc20z = mockMinter.setSale(address(mock1155), tokenId1);

        uint256 quantity = 5;

        address excessRefundRecipient = makeAddr("excessRefundRecipient");
        uint256 maxEthToSpend = 2 ether;
        uint160 sqrtPriceLimitX96 = 1000;
        string memory comment = "test comment";

        IComments.CommentIdentifier memory expectedCommentIdentifier = _expectedCommentIdentifier(commenter, address(mock1155), tokenId1);
        bytes32 expectedCommentId = comments.hashCommentIdentifier(expectedCommentIdentifier);

        uint256 valueToSpend = 1 ether;
        vm.deal(commenter, valueToSpend);

        vm.expectEmit(true, true, true, true);
        emit IComments.Commented(expectedCommentId, expectedCommentIdentifier, bytes32(0), emptyCommentIdentifier, 0, comment, block.timestamp, address(0));
        vm.expectEmit(true, true, true, true);
        emit ICallerAndCommenter.SwappedOnSecondaryAndCommented(
            expectedCommentId,
            expectedCommentIdentifier,
            quantity,
            comment,
            ICallerAndCommenter.SwapDirection.BUY
        );

        vm.expectCall(
            address(mockSecondarySwap),
            valueToSpend,
            abi.encodeWithSelector(ISecondarySwap.buy1155.selector, erc20z, quantity, commenter, excessRefundRecipient, maxEthToSpend, sqrtPriceLimitX96)
        );

        vm.prank(commenter);
        callerAndCommenter.buyOnSecondaryAndComment{value: valueToSpend}({
            commenter: commenter,
            quantity: quantity,
            collection: address(mock1155),
            tokenId: tokenId1,
            excessRefundRecipient: payable(excessRefundRecipient),
            maxEthToSpend: maxEthToSpend,
            sqrtPriceLimitX96: sqrtPriceLimitX96,
            comment: comment
        });
    }

    function testBuyOnSecondaryAndComment_revertsWhenSaleNotSet() public {
        vm.expectRevert(abi.encodeWithSelector(ICallerAndCommenter.SaleNotSet.selector, address(mock1155), tokenId1));
        vm.prank(commenter);
        callerAndCommenter.buyOnSecondaryAndComment({
            commenter: commenter,
            quantity: 1,
            collection: address(mock1155),
            tokenId: tokenId1,
            excessRefundRecipient: payable(address(0)),
            maxEthToSpend: 0,
            sqrtPriceLimitX96: 0,
            comment: "test comment"
        });
    }

    function testBuyOnSecondaryAndComment_revertsWhenCommenterMismatch() public {
        address commenter2 = makeAddr("commenter2");
        vm.expectRevert(abi.encodeWithSelector(ICallerAndCommenter.CommenterMismatch.selector, commenter2, commenter));
        vm.prank(commenter2);
        callerAndCommenter.buyOnSecondaryAndComment({
            commenter: commenter,
            quantity: 1,
            collection: address(mock1155),
            tokenId: tokenId1,
            excessRefundRecipient: payable(address(0)),
            maxEthToSpend: 0,
            sqrtPriceLimitX96: 0,
            comment: "test comment"
        });
    }

    function testBuyOnSecondaryAndCommentWhenNoCommentDoesNotComment() public {
        uint256 quantity = 1;
        uint256 maxEthToSpend = 0.2 ether;
        uint160 sqrtPriceLimitX96 = 0;
        address excessRefundRecipient = address(0);

        mockMinter.setSale(address(mock1155), tokenId1);

        vm.prank(commenter);
        IComments.CommentIdentifier memory result = callerAndCommenter.buyOnSecondaryAndComment({
            commenter: commenter,
            quantity: quantity,
            collection: address(mock1155),
            tokenId: tokenId1,
            excessRefundRecipient: payable(excessRefundRecipient),
            maxEthToSpend: maxEthToSpend,
            sqrtPriceLimitX96: sqrtPriceLimitX96,
            comment: ""
        });

        assertEq(result.commenter, address(0));
        assertEq(result.contractAddress, address(0));
        assertEq(result.tokenId, 0);
        assertEq(result.nonce, bytes32(0));
    }

    function upgradeForkCallerAndCommenterToNewImplementation() internal {
        // upgrade the current caller and commenter on the fork to the new implementation
        address COMMENTS = 0x7777777C2B3132e03a65721a41745C07170a5877;
        address ZORA_TIMED_SALE_STRATEGY = 0x777777722D078c97c6ad07d9f36801e653E356Ae;
        address SECONDARY_SWAP = 0x777777EDF27Ac61671e3D5718b10bf6a8802f9f1;
        // deploy the new implementation
        CallerAndCommenterImpl callerAndCallerImp = new CallerAndCommenterImpl(COMMENTS, ZORA_TIMED_SALE_STRATEGY, SECONDARY_SWAP, SPARKS_VALUE);
        // here we override the caller and commenter with the current one on the fork
        callerAndCommenter = ICallerAndCommenter(0x77777775C5074b74540d9cC63Dd840A8c692B4B5);
        // upgrade to the new implementation
        address owner = OwnableUpgradeable(address(callerAndCommenter)).owner();
        vm.prank(owner);
        UUPSUpgradeable(address(callerAndCommenter)).upgradeToAndCall(address(callerAndCallerImp), "");
    }

    function testFork_buyOnSecondaryAndComment() public {
        // upgrade the forked caller and commenter to the new implementation
        upgradeForkCallerAndCommenterToNewImplementation();
        // this is a known zora test collection where we can secondary swap
        address test1155Address = 0xE79585bF83BbBfAE0fB80222b0a72F2c1D040612;
        uint256 testTokenId = 1;

        address excessRefundRecipient = makeAddr("excessRefundRecipient");
        uint256 maxEthToSpend = 237222215770897;
        uint160 sqrtPriceLimitX96 = 0;
        string memory comment = "test comment";

        IComments.CommentIdentifier memory expectedCommentIdentifier = IComments.CommentIdentifier({
            commenter: commenter,
            contractAddress: test1155Address,
            tokenId: testTokenId,
            // we need to get the nonce from the fork comments contract
            nonce: callerAndCommenter.comments().nextNonce()
        });
        bytes32 expectedCommentId = callerAndCommenter.comments().hashCommentIdentifier(expectedCommentIdentifier);

        uint256 quantity = 1;
        uint256 valueToSpend = maxEthToSpend;
        vm.deal(commenter, valueToSpend);

        vm.expectEmit(true, true, true, true);
        emit IComments.Commented(expectedCommentId, expectedCommentIdentifier, bytes32(0), emptyCommentIdentifier, 0, comment, block.timestamp, address(0));
        vm.expectEmit(true, true, true, true);
        emit ICallerAndCommenter.SwappedOnSecondaryAndCommented(
            expectedCommentId,
            expectedCommentIdentifier,
            quantity,
            comment,
            ICallerAndCommenter.SwapDirection.BUY
        );

        // call the caller and commenter contract
        vm.prank(commenter);
        callerAndCommenter.buyOnSecondaryAndComment{value: valueToSpend}({
            commenter: commenter,
            quantity: quantity,
            collection: test1155Address,
            tokenId: testTokenId,
            excessRefundRecipient: payable(excessRefundRecipient),
            maxEthToSpend: maxEthToSpend,
            sqrtPriceLimitX96: sqrtPriceLimitX96,
            comment: comment
        });
    }

    function testPermitBuyOnSecondaryAndComment() public {
        uint256 quantity = 5;
        uint256 valueToSpend = 1 ether;

        address contractAddress = address(mock1155);
        uint256 tokenId = tokenId1;

        string memory comment = "test comment";

        address erc20z = mockMinter.setSale(contractAddress, tokenId);

        ICallerAndCommenter.PermitBuyOnSecondaryAndComment memory permit = _createPermitBuy(
            commenter,
            quantity,
            contractAddress,
            tokenId,
            2 ether,
            1000,
            comment,
            block.timestamp + 1 hours
        );

        bytes memory signature = _signPermit(permit, commenterPrivateKey);

        IComments.CommentIdentifier memory expectedCommentIdentifier = _expectedCommentIdentifier(commenter, contractAddress, tokenId);

        bytes32 expectedCommentId = comments.hashCommentIdentifier(expectedCommentIdentifier);

        vm.deal(commenter, valueToSpend);
        vm.expectEmit(true, true, true, true);
        emit IComments.Commented(expectedCommentId, expectedCommentIdentifier, bytes32(0), emptyCommentIdentifier, 0, comment, block.timestamp, address(0));
        vm.expectEmit(true, true, true, true);
        emit ICallerAndCommenter.SwappedOnSecondaryAndCommented(
            expectedCommentId,
            expectedCommentIdentifier,
            quantity,
            comment,
            ICallerAndCommenter.SwapDirection.BUY
        );

        vm.expectCall(
            address(mockSecondarySwap),
            valueToSpend,
            abi.encodeWithSelector(
                ISecondarySwap.buy1155.selector,
                erc20z,
                quantity,
                commenter,
                permit.commenter,
                permit.maxEthToSpend,
                permit.sqrtPriceLimitX96
            )
        );

        IComments.CommentIdentifier memory result = callerAndCommenter.permitBuyOnSecondaryAndComment{value: valueToSpend}(permit, signature);

        assertEq(result.commenter, commenter);
        assertEq(result.contractAddress, contractAddress);
        assertEq(result.tokenId, tokenId);
        assertEq(result.nonce, bytes32(0));

        // validate that the comment was created
        (, bool exists) = comments.hashAndCheckCommentExists(expectedCommentIdentifier);
        assertEq(exists, true);
    }

    function testPermitBuyOnSecondaryAndComment_ExpiredDeadline() public {
        ICallerAndCommenter.PermitBuyOnSecondaryAndComment memory permit = _createPermitBuy(
            commenter,
            1,
            address(mock1155),
            tokenId1,
            1 ether,
            1000,
            "test comment",
            block.timestamp - 1 // Expired deadline
        );

        bytes memory signature = _signPermit(permit, commenterPrivateKey);

        vm.expectRevert(abi.encodeWithSelector(IComments.ERC2612ExpiredSignature.selector, permit.deadline));
        callerAndCommenter.permitBuyOnSecondaryAndComment{value: 1 ether}(permit, signature);
    }

    function testPermitBuyOnSecondaryAndComment_InvalidSignature() public {
        ICallerAndCommenter.PermitBuyOnSecondaryAndComment memory permit = _createPermitBuy(
            commenter,
            1,
            address(mock1155),
            tokenId1,
            1 ether,
            1000,
            "test comment",
            block.timestamp + 1 hours
        );

        bytes memory signature = _signPermit(permit, 5); // Wrong signer

        vm.expectRevert(IComments.InvalidSignature.selector);
        callerAndCommenter.permitBuyOnSecondaryAndComment{value: 1 ether}(permit, signature);
    }

    function testPermitBuyOnSecondaryAndComment_IncorrectDestinationChain() public {
        ICallerAndCommenter.PermitBuyOnSecondaryAndComment memory permit = _createPermitBuy(
            commenter,
            1,
            address(mock1155),
            tokenId1,
            1 ether,
            1000,
            "test comment",
            block.timestamp + 1 hours
        );
        permit.destinationChainId = uint32(block.chainid) + 1; // Incorrect destination chain

        bytes memory signature = _signPermit(permit, commenterPrivateKey);

        vm.expectRevert(abi.encodeWithSelector(ICallerAndCommenter.IncorrectDestinationChain.selector, permit.destinationChainId));
        callerAndCommenter.permitBuyOnSecondaryAndComment{value: 1 ether}(permit, signature);
    }

    function testSellOnSecondaryAndComment() public {
        // setup the sale so that we have a link between the erc20z and the 1155
        mockMinter.setSale(address(mock1155), tokenId1);

        uint256 quantityToSwap = 5;
        mock1155.mint(commenter, tokenId1, quantityToSwap, "");

        address payable recipient = payable(makeAddr("recipient"));
        uint256 minEthToAcquire = 1 ether;
        uint160 sqrtPriceLimitX96 = 1000;
        string memory comment = "test comment";

        IComments.CommentIdentifier memory expectedCommentIdentifier = _expectedCommentIdentifier(commenter, address(mock1155), tokenId1);
        bytes32 expectedCommentId = comments.hashCommentIdentifier(expectedCommentIdentifier);

        bytes memory expectedData = abi.encode(recipient, minEthToAcquire, sqrtPriceLimitX96);

        // commenter needs to approve the caller to transfer the 1155s
        // since it is to transfer to the secondary swap
        vm.prank(commenter);
        IERC1155(address(mock1155)).setApprovalForAll(address(callerAndCommenter), true);

        vm.expectEmit(true, true, true, true);
        emit IComments.Commented({
            commentId: expectedCommentId,
            commentIdentifier: expectedCommentIdentifier,
            replyToId: bytes32(0),
            replyTo: emptyCommentIdentifier,
            sparksQuantity: 1,
            text: comment,
            timestamp: block.timestamp,
            referrer: address(0)
        });
        vm.expectEmit(true, true, true, true);
        emit ICallerAndCommenter.SwappedOnSecondaryAndCommented(
            expectedCommentId,
            expectedCommentIdentifier,
            quantityToSwap,
            comment,
            ICallerAndCommenter.SwapDirection.SELL
        );

        // make sure the mock secondary swap received the 1155s
        // using the expected call
        vm.expectCall(
            address(mockSecondarySwap),
            0,
            abi.encodeWithSelector(IERC1155Receiver.onERC1155Received.selector, address(callerAndCommenter), commenter, tokenId1, quantityToSwap, expectedData)
        );

        vm.deal(commenter, SPARKS_VALUE);
        vm.prank(commenter);
        callerAndCommenter.sellOnSecondaryAndComment{value: SPARKS_VALUE}(
            commenter,
            quantityToSwap,
            address(mock1155),
            tokenId1,
            recipient,
            minEthToAcquire,
            sqrtPriceLimitX96,
            comment
        );

        // make sure the mock secondary swap received the 1155s
        assertEq(IERC1155(address(mock1155)).balanceOf(address(mockSecondarySwap), tokenId1), quantityToSwap);
    }

    function testFork_sellOnSecondaryAndComment() public {
        // upgrade the forked caller and commenter to the new implementation
        upgradeForkCallerAndCommenterToNewImplementation();
        // this is a known zora test collection where we can secondary swap
        address test1155Address = 0xE79585bF83BbBfAE0fB80222b0a72F2c1D040612;
        uint256 testTokenId = 1;

        uint256 quantityToBuy = 5;

        uint256 maxEthToSpend = 237222215770897 * quantityToBuy;
        uint256 valueToSpend = maxEthToSpend;

        // first we need to buy the 1155s on secondary
        vm.deal(commenter, valueToSpend);
        vm.prank(commenter);
        callerAndCommenter.buyOnSecondaryAndComment{value: valueToSpend}({
            commenter: commenter,
            quantity: quantityToBuy,
            collection: test1155Address,
            tokenId: testTokenId,
            excessRefundRecipient: payable(commenter),
            maxEthToSpend: maxEthToSpend,
            sqrtPriceLimitX96: 0,
            comment: "test comment when buying"
        });

        // now we can sell the 1155s on secondary

        uint256 quantityToSell = 3;
        string memory sellingComment = "test comment when selling";

        vm.prank(commenter);
        IERC1155(address(test1155Address)).setApprovalForAll(address(callerAndCommenter), true);

        // perform the sell
        vm.deal(commenter, SPARKS_VALUE);
        vm.prank(commenter);
        callerAndCommenter.sellOnSecondaryAndComment{value: SPARKS_VALUE}({
            commenter: commenter,
            quantity: quantityToSell,
            collection: test1155Address,
            tokenId: testTokenId,
            recipient: payable(commenter),
            minEthToAcquire: 0,
            sqrtPriceLimitX96: 0,
            comment: sellingComment
        });
    }

    function testSellOnSecondaryAndComment_CommenterMismatch() public {
        vm.expectRevert(abi.encodeWithSelector(ICallerAndCommenter.CommenterMismatch.selector, commenter, makeAddr("other")));
        vm.prank(commenter);
        callerAndCommenter.sellOnSecondaryAndComment(makeAddr("other"), 1, address(mock1155), tokenId1, payable(address(0)), 1 ether, 1000, "test comment");
    }

    function testSellOnSecondaryAndComment_SaleNotSet() public {
        uint256 quantityToSwap = 5;
        mock1155.mint(commenter, tokenId1, quantityToSwap, "");
        vm.prank(commenter);
        IERC1155(address(mock1155)).setApprovalForAll(address(callerAndCommenter), true);

        vm.expectRevert(ISecondarySwap.SaleNotSet.selector);
        vm.prank(commenter);
        vm.deal(commenter, SPARKS_VALUE);
        callerAndCommenter.sellOnSecondaryAndComment{value: SPARKS_VALUE}(
            commenter,
            1,
            address(mock1155),
            tokenId1,
            payable(address(0)),
            1 ether,
            1000,
            "test comment"
        );
    }

    function testSellOnSecondaryAndComment_RevertsWhenNotOneSparkAndACommentIsSent(uint16 sparksQuantity, bool commentIsSent) public {
        uint256 valueToSend = sparksQuantity * SPARKS_VALUE;
        // setup the sale so that we have a link between the erc20z and the 1155
        mockMinter.setSale(address(mock1155), tokenId1);

        uint256 quantityToSwap = 5;
        mock1155.mint(commenter, tokenId1, quantityToSwap, "");

        address recipient = makeAddr("recipient");
        uint256 minEthToAcquire = 1 ether;
        uint160 sqrtPriceLimitX96 = 1000;
        string memory comment = commentIsSent ? "test comment" : "";

        // commenter needs to approve the caller to transfer the 1155s
        // since it is to transfer to the secondary swap
        vm.prank(commenter);
        IERC1155(address(mock1155)).setApprovalForAll(address(callerAndCommenter), true);

        // if we are sending a comment, we should be required to send one spark
        if (commentIsSent) {
            if (sparksQuantity != 1) {
                vm.expectRevert(abi.encodeWithSelector(ICallerAndCommenter.WrongValueSent.selector, SPARKS_VALUE, valueToSend));
            }
        } else {
            // if we are not sending a comment, we should not send any ETH
            if (valueToSend != 0) {
                vm.expectRevert(abi.encodeWithSelector(ICallerAndCommenter.WrongValueSent.selector, 0, valueToSend));
            }
        }

        vm.deal(commenter, valueToSend);
        vm.prank(commenter);
        callerAndCommenter.sellOnSecondaryAndComment{value: valueToSend}(
            commenter,
            quantityToSwap,
            address(mock1155),
            tokenId1,
            payable(recipient),
            minEthToAcquire,
            sqrtPriceLimitX96,
            comment
        );
    }

    function _createPermitBuy(
        address _commenter,
        uint256 _quantity,
        address _collection,
        uint256 _tokenId,
        uint256 _maxEthToSpend,
        uint160 _sqrtPriceLimitX96,
        string memory _comment,
        uint256 _deadline
    ) internal view returns (ICallerAndCommenter.PermitBuyOnSecondaryAndComment memory) {
        return
            ICallerAndCommenter.PermitBuyOnSecondaryAndComment({
                commenter: _commenter,
                quantity: _quantity,
                collection: _collection,
                tokenId: _tokenId,
                maxEthToSpend: _maxEthToSpend,
                sqrtPriceLimitX96: _sqrtPriceLimitX96,
                comment: _comment,
                deadline: _deadline,
                nonce: bytes32(0),
                sourceChainId: uint32(block.chainid),
                destinationChainId: uint32(block.chainid)
            });
    }

    function _signPermit(ICallerAndCommenter.PermitBuyOnSecondaryAndComment memory _permit, uint256 _privateKey) internal view returns (bytes memory) {
        bytes32 digest = callerAndCommenter.hashPermitBuyOnSecondaryAndComment(_permit);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_privateKey, digest);
        return abi.encodePacked(r, s, v);
    }
}
