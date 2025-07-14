// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";

import {ZoraSparks1155} from "../../src/ZoraSparks1155.sol";
import {Mock1155} from "../mocks/Mock1155.sol";
import {ContractCreationConfig, PremintConfigV2, TokenCreationConfigV2, MintArguments, PremintResult} from "@zoralabs/shared-contracts/entities/Premint.sol";
import {ZoraSparksManagerImpl} from "../../src/ZoraSparksManagerImpl.sol";
import {ZoraSparksFixtures} from "../../test/fixtures/ZoraSparksFixtures.sol";
import {SponsoredSparksSpender, SponsoredMintBatch, ISponsoredSparksSpenderAction, ISponsoredSparksSpender, SponsoredSpend} from "../../src/helpers/SponsoredSparksSpender.sol";
import {TokenConfig} from "../../src/ZoraSparksTypes.sol";
import {IZoraSparks1155Managed} from "../../src/interfaces/IZoraSparks1155Managed.sol";

contract MockReceiverContract {
    event HasCall(uint256 value, string argument);

    bool public received;

    function mockReceiveFunction(string memory argument) external payable {
        if (bytes(argument).length == 0) {
            revert("Argument must not be empty");
        }
        emit HasCall(msg.value, argument);
        received = true;
    }
}

contract NonPayableContract {}

contract SponsoredSparksSpenderTest is Test {
    address admin = makeAddr("admin");
    address proxyAdmin = makeAddr("proxyAdmin");
    address collector;
    uint256 collectorPrivateKey;
    address verifier;
    uint256 verifierPrivateKey;

    ZoraSparks1155 sparks;

    uint256 initialTokenId = 995;
    uint256 initialTokenPrice = 0.086 ether;

    Mock1155 mock1155;

    ContractCreationConfig contractCreationConfig;

    TokenCreationConfigV2 tokenCreationConfig;

    PremintConfigV2 premintConfig;

    MintArguments mintArguments;

    address signerContract = makeAddr("signerContract");

    ZoraSparksManagerImpl sparksManager;

    // build main contract which were testing
    SponsoredSparksSpender sponsoredSparksSpender;

    function setUp() external {
        (verifier, verifierPrivateKey) = makeAddrAndKey("verifier");
        (collector, collectorPrivateKey) = makeAddrAndKey("collector");
        (sparks, sparksManager) = ZoraSparksFixtures.setupSparksProxyWithMockPreminter(proxyAdmin, admin, initialTokenId, initialTokenPrice);
        mock1155 = new Mock1155();

        sponsoredSparksSpender = new SponsoredSparksSpender(sparks, admin, new address[](0));
        vm.prank(admin);
        sponsoredSparksSpender.setVerifierStatus(verifier, true);
        contractCreationConfig = ContractCreationConfig({contractAdmin: makeAddr("contractAdmin"), contractURI: "contractURI", contractName: "contractName"});

        tokenCreationConfig = TokenCreationConfigV2({
            tokenURI: "tokenURI",
            maxSupply: 100,
            maxTokensPerAddress: 10,
            pricePerToken: 0,
            mintStart: 0,
            mintDuration: 0,
            royaltyBPS: 0,
            payoutRecipient: makeAddr("payoutRecipient"),
            fixedPriceMinter: makeAddr("fixedPriceMinter"),
            createReferral: makeAddr("creator")
        });

        vm.prank(sparksManager.owner());
        sparksManager.createToken(1, TokenConfig({price: 0.5 ether, tokenAddress: address(0), redeemHandler: address(0)}));

        premintConfig = PremintConfigV2({tokenConfig: tokenCreationConfig, uid: 0, version: 0, deleted: false});

        mintArguments = MintArguments({mintRecipient: makeAddr("mintRecipient"), mintComment: "mintComment", mintRewardsRecipients: new address[](0)});
    }

    function test_sparksUsedNonce() external {
        // Fund Sponsored Sparks Spender
        sponsoredSparksSpender.fund{value: 10 ether}();

        // 1. Mint some eth based tokens
        uint256[] memory quantities = new uint256[](1);
        quantities[0] = 3;

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 1;

        vm.deal(collector, 100 ether);

        vm.startPrank(collector);
        sparksManager.mintWithEth{value: 0.5 ether * quantities[0] * 2}(1, quantities[0] * 2, collector);
        vm.stopPrank();

        // 2. Setup unwrap call
        // setup mock receiver contract that will receive eith with some call
        MockReceiverContract mockReceiverContract = new MockReceiverContract();

        bytes memory mockReceiverCall = abi.encodeWithSelector(mockReceiverContract.mockReceiveFunction.selector, "randomArgument");

        uint256 totalAmount = 1.5 ether;

        SponsoredMintBatch memory sponsoredMint = SponsoredMintBatch({
            verifier: verifier,
            from: collector,
            destination: payable(address(mockReceiverContract)),
            data: mockReceiverCall,
            totalAmount: totalAmount,
            expectedRedeemAmount: 1.5 ether,
            ids: tokenIds,
            quantities: quantities,
            nonce: 1,
            deadline: block.timestamp + 100
        });

        // encode call to call on the receiver
        bytes memory encodedCall = abi.encodeWithSelector(
            ISponsoredSparksSpenderAction.sponsoredMintBatch.selector,
            sponsoredMint,
            _signSponsoredMintAction(sponsoredMint, verifierPrivateKey)
        );

        // receiver should be called with the value to send, and the encoded call above
        vm.expectCall(address(mockReceiverContract), totalAmount, abi.encodeCall(mockReceiverContract.mockReceiveFunction, "randomArgument"));

        // make invalid block time
        vm.warp(block.timestamp + 120);
        vm.prank(collector);
        vm.expectRevert(ISponsoredSparksSpender.SignatureExpired.selector);
        sparks.safeBatchTransferFrom(collector, address(sponsoredSparksSpender), tokenIds, quantities, encodedCall);

        vm.warp(0);
        vm.prank(collector);
        sparks.safeBatchTransferFrom(collector, address(sponsoredSparksSpender), tokenIds, quantities, encodedCall);

        vm.prank(collector);
        vm.expectRevert(ISponsoredSparksSpender.NonceUsed.selector);
        sparks.safeBatchTransferFrom(collector, address(sponsoredSparksSpender), tokenIds, quantities, encodedCall);

        assertEq(address(mockReceiverContract).balance, totalAmount);
    }

    function test_sparksWrongVerifier() external {
        // Fund Sponsored Sparks Spender
        sponsoredSparksSpender.fund{value: 10 ether}();

        // 1. Mint some eth based tokens
        uint256[] memory quantities = new uint256[](1);
        quantities[0] = 3;

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 1;

        vm.deal(collector, 100 ether);

        vm.startPrank(collector);
        sparksManager.mintWithEth{value: 0.5 ether * quantities[0] * 2}(1, quantities[0] * 2, collector);
        vm.stopPrank();

        // 2. Setup unwrap call
        // setup mock receiver contract that will receive eith with some call
        MockReceiverContract mockReceiverContract = new MockReceiverContract();

        bytes memory mockReceiverCall = abi.encodeWithSelector(mockReceiverContract.mockReceiveFunction.selector, "randomArgument");

        (address wrongVerifier, uint256 wrongPkey) = makeAddrAndKey("wrongVerifier");

        SponsoredMintBatch memory sponsoredMint = SponsoredMintBatch({
            verifier: wrongVerifier,
            from: collector,
            destination: payable(address(mockReceiverContract)),
            data: mockReceiverCall,
            totalAmount: 1.5 ether,
            expectedRedeemAmount: 0.258 ether,
            ids: tokenIds,
            quantities: quantities,
            nonce: 1,
            deadline: block.timestamp + 100
        });

        // encode call to call on the receiver
        bytes memory encodedCall = abi.encodeWithSelector(
            ISponsoredSparksSpenderAction.sponsoredMintBatch.selector,
            sponsoredMint,
            _signSponsoredMintAction(sponsoredMint, wrongPkey)
        );

        // wrong verifier
        vm.prank(collector);
        vm.expectRevert(abi.encodeWithSelector(ISponsoredSparksSpender.VerifierNotAllowed.selector, wrongVerifier));
        sparks.safeBatchTransferFrom(collector, address(sponsoredSparksSpender), tokenIds, quantities, encodedCall);
    }

    function test_sparksWrongIdsValue() external {
        // Fund Sponsored Sparks Spender
        sponsoredSparksSpender.fund{value: 10 ether}();

        // 1. Mint some eth based tokens
        uint256[] memory quantities = new uint256[](1);
        quantities[0] = 3;

        uint256[] memory wrongId = new uint256[](1);
        wrongId[0] = 10;

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 1;

        vm.deal(collector, 100 ether);

        vm.startPrank(collector);
        sparksManager.mintWithEth{value: 0.5 ether * quantities[0] * 2}(1, quantities[0] * 2, collector);
        vm.stopPrank();

        // 2. Setup unwrap call
        // setup mock receiver contract that will receive eith with some call
        MockReceiverContract mockReceiverContract = new MockReceiverContract();

        bytes memory mockReceiverCall = abi.encodeWithSelector(mockReceiverContract.mockReceiveFunction.selector, "randomArgument");

        SponsoredMintBatch memory sponsoredMint = SponsoredMintBatch({
            verifier: verifier,
            from: collector,
            destination: payable(address(mockReceiverContract)),
            data: mockReceiverCall,
            totalAmount: 1.5 ether,
            expectedRedeemAmount: 0.258 ether,
            ids: wrongId,
            quantities: quantities,
            nonce: 1,
            deadline: block.timestamp + 100
        });

        // encode call to call on the receiver
        bytes memory encodedCall = abi.encodeWithSelector(
            ISponsoredSparksSpenderAction.sponsoredMintBatch.selector,
            sponsoredMint,
            _signSponsoredMintAction(sponsoredMint, verifierPrivateKey)
        );

        // wrong length
        vm.prank(collector);
        vm.expectRevert(ISponsoredSparksSpender.IdsMismatch.selector);
        sparks.safeBatchTransferFrom(collector, address(sponsoredSparksSpender), tokenIds, quantities, encodedCall);
    }

    function test_sparksWrongQuantitiesLength() external {
        // Fund Sponsored Sparks Spender
        sponsoredSparksSpender.fund{value: 10 ether}();

        // 1. Mint some eth based tokens
        uint256[] memory quantities = new uint256[](1);
        quantities[0] = 3;

        uint256[] memory wrongQuantities = new uint256[](2);
        wrongQuantities[0] = 3;
        wrongQuantities[1] = 2;

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 1;

        vm.deal(collector, 100 ether);

        vm.startPrank(collector);
        sparksManager.mintWithEth{value: 0.5 ether * quantities[0] * 2}(1, quantities[0] * 2, collector);
        vm.stopPrank();

        // 2. Setup unwrap call
        // setup mock receiver contract that will receive eith with some call
        MockReceiverContract mockReceiverContract = new MockReceiverContract();

        bytes memory mockReceiverCall = abi.encodeWithSelector(mockReceiverContract.mockReceiveFunction.selector, "randomArgument");

        SponsoredMintBatch memory sponsoredMint = SponsoredMintBatch({
            verifier: verifier,
            from: collector,
            destination: payable(address(mockReceiverContract)),
            data: mockReceiverCall,
            totalAmount: 1.5 ether,
            expectedRedeemAmount: 0.258 ether,
            ids: tokenIds,
            quantities: wrongQuantities,
            nonce: 1,
            deadline: block.timestamp + 100
        });

        // encode call to call on the receiver
        bytes memory encodedCall = abi.encodeWithSelector(
            ISponsoredSparksSpenderAction.sponsoredMintBatch.selector,
            sponsoredMint,
            _signSponsoredMintAction(sponsoredMint, verifierPrivateKey)
        );

        // wrong length
        vm.prank(collector);
        vm.expectRevert(ISponsoredSparksSpender.LengthMismatch.selector);
        sparks.safeBatchTransferFrom(collector, address(sponsoredSparksSpender), tokenIds, quantities, encodedCall);
    }

    function test_sparksWrongQuantityValue() external {
        // Fund Sponsored Sparks Spender
        sponsoredSparksSpender.fund{value: 10 ether}();

        // 1. Mint some eth based tokens
        uint256[] memory quantities = new uint256[](1);
        quantities[0] = 3;

        uint256[] memory wrongQuantity = new uint256[](1);
        wrongQuantity[0] = 4;

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 1;

        vm.deal(collector, 100 ether);

        vm.startPrank(collector);
        sparksManager.mintWithEth{value: 0.5 ether * quantities[0] * 2}(1, quantities[0] * 2, collector);
        vm.stopPrank();

        // 2. Setup unwrap call
        // setup mock receiver contract that will receive eith with some call
        MockReceiverContract mockReceiverContract = new MockReceiverContract();

        bytes memory mockReceiverCall = abi.encodeWithSelector(mockReceiverContract.mockReceiveFunction.selector, "randomArgument");

        SponsoredMintBatch memory sponsoredMint = SponsoredMintBatch({
            verifier: verifier,
            from: collector,
            destination: payable(address(mockReceiverContract)),
            data: mockReceiverCall,
            totalAmount: 1.5 ether,
            expectedRedeemAmount: 0.258 ether,
            ids: tokenIds,
            quantities: wrongQuantity,
            nonce: 1,
            deadline: block.timestamp + 100
        });

        // encode call to call on the receiver
        bytes memory encodedCall = abi.encodeWithSelector(
            ISponsoredSparksSpenderAction.sponsoredMintBatch.selector,
            sponsoredMint,
            _signSponsoredMintAction(sponsoredMint, verifierPrivateKey)
        );

        // wrong length
        vm.prank(collector);
        vm.expectRevert(ISponsoredSparksSpender.ValuesMismatch.selector);
        sparks.safeBatchTransferFrom(collector, address(sponsoredSparksSpender), tokenIds, quantities, encodedCall);
    }

    function test_sparksWrongIdsLength() external {
        // Fund Sponsored Sparks Spender
        sponsoredSparksSpender.fund{value: 10 ether}();

        // 1. Mint some eth based tokens
        uint256[] memory quantities = new uint256[](1);
        quantities[0] = 3;

        uint256[] memory wrongQuantities = new uint256[](2);
        wrongQuantities[0] = 3;
        wrongQuantities[1] = 2;

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 1;

        vm.deal(collector, 100 ether);

        vm.startPrank(collector);
        sparksManager.mintWithEth{value: 0.5 ether * quantities[0] * 2}(1, quantities[0] * 2, collector);
        vm.stopPrank();

        // 2. Setup unwrap call
        // setup mock receiver contract that will receive eith with some call
        MockReceiverContract mockReceiverContract = new MockReceiverContract();

        bytes memory mockReceiverCall = abi.encodeWithSelector(mockReceiverContract.mockReceiveFunction.selector, "randomArgument");

        SponsoredMintBatch memory sponsoredMint = SponsoredMintBatch({
            verifier: verifier,
            from: collector,
            destination: payable(address(mockReceiverContract)),
            data: mockReceiverCall,
            totalAmount: 1.5 ether,
            expectedRedeemAmount: 0.258 ether,
            ids: tokenIds,
            quantities: wrongQuantities,
            nonce: 1,
            deadline: block.timestamp + 100
        });

        // encode call to call on the receiver
        bytes memory encodedCall = abi.encodeWithSelector(
            ISponsoredSparksSpenderAction.sponsoredMintBatch.selector,
            sponsoredMint,
            _signSponsoredMintAction(sponsoredMint, verifierPrivateKey)
        );

        // wrong length
        vm.prank(collector);
        vm.expectRevert(ISponsoredSparksSpender.LengthMismatch.selector);
        sparks.safeBatchTransferFrom(collector, address(sponsoredSparksSpender), tokenIds, quantities, encodedCall);
    }

    function test_sparksWrongActionId() external {
        // Fund Sponsored Sparks Spender
        sponsoredSparksSpender.fund{value: 10 ether}();

        // 1. Mint some eth based tokens
        uint256[] memory quantities = new uint256[](1);
        quantities[0] = 3;

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 1;

        vm.deal(collector, 100 ether);

        vm.startPrank(collector);
        sparksManager.mintWithEth{value: 0.5 ether * quantities[0] * 2}(1, quantities[0] * 2, collector);
        vm.stopPrank();

        // 2. Setup unwrap call
        // setup mock receiver contract that will receive eith with some call
        MockReceiverContract mockReceiverContract = new MockReceiverContract();

        bytes memory mockReceiverCall = abi.encodeWithSelector(mockReceiverContract.mockReceiveFunction.selector, "randomArgument");

        SponsoredMintBatch memory sponsoredMint = SponsoredMintBatch({
            verifier: verifier,
            from: collector,
            destination: payable(address(mockReceiverContract)),
            data: mockReceiverCall,
            totalAmount: 1.5 ether,
            expectedRedeemAmount: 0.258 ether,
            ids: tokenIds,
            quantities: quantities,
            nonce: 1,
            deadline: block.timestamp + 100
        });

        // encode call to call on the receiver
        bytes memory encodedCall = abi.encodeWithSelector(
            mockReceiverContract.mockReceiveFunction.selector,
            sponsoredMint,
            _signSponsoredMintAction(sponsoredMint, verifierPrivateKey)
        );

        // wrong selector
        vm.prank(collector);
        vm.expectRevert(ISponsoredSparksSpender.UnknownAction.selector);
        sparks.safeBatchTransferFrom(collector, address(sponsoredSparksSpender), tokenIds, quantities, encodedCall);
    }

    function test_sparksWrongSignature() external {
        // Fund Sponsored Sparks Spender
        sponsoredSparksSpender.fund{value: 10 ether}();

        // 1. Mint some eth based tokens
        uint256[] memory quantities = new uint256[](1);
        quantities[0] = 3;

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 1;

        vm.deal(collector, 100 ether);

        vm.startPrank(collector);
        sparksManager.mintWithEth{value: 0.5 ether * quantities[0] * 2}(1, quantities[0] * 2, collector);
        vm.stopPrank();

        // 2. Setup unwrap call
        // setup mock receiver contract that will receive eith with some call
        MockReceiverContract mockReceiverContract = new MockReceiverContract();

        bytes memory mockReceiverCall = abi.encodeWithSelector(mockReceiverContract.mockReceiveFunction.selector, "randomArgument");

        (, uint256 wrongPkey) = makeAddrAndKey("wrongVerifier");

        SponsoredMintBatch memory sponsoredMint = SponsoredMintBatch({
            verifier: verifier,
            from: collector,
            destination: payable(address(mockReceiverContract)),
            data: mockReceiverCall,
            totalAmount: 1.5 ether,
            expectedRedeemAmount: 0.258 ether,
            ids: tokenIds,
            quantities: quantities,
            nonce: 1,
            deadline: block.timestamp + 100
        });

        // encode call to call on the receiver
        bytes memory encodedCall = abi.encodeWithSelector(
            ISponsoredSparksSpenderAction.sponsoredMintBatch.selector,
            sponsoredMint,
            _signSponsoredMintAction(sponsoredMint, wrongPkey)
        );

        // wrong signature
        vm.prank(collector);
        vm.expectRevert(ISponsoredSparksSpender.InvalidSignature.selector);
        sparks.safeBatchTransferFrom(collector, address(sponsoredSparksSpender), tokenIds, quantities, encodedCall);
    }

    function test_sparksWithAdditionalValueUnwrap() external {
        // Fund Sponsored Sparks Spender
        sponsoredSparksSpender.fund{value: 10 ether}();

        // 1. Mint some eth based tokens
        uint256[] memory quantities = new uint256[](2);
        quantities[0] = 3;
        quantities[1] = 2;

        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 1;
        tokenIds[1] = 3;

        vm.deal(collector, 100 ether);

        vm.startPrank(collector);
        sparksManager.mintWithEth{value: 0.5 ether * quantities[0]}(1, quantities[0], collector);
        vm.stopPrank();

        vm.prank(admin);
        sparksManager.createToken(tokenIds[1], TokenConfig({price: 0.5 ether, tokenAddress: address(0), redeemHandler: address(0)}));

        vm.startPrank(collector);
        sparksManager.mintWithEth{value: 0.5 ether * quantities[1]}(tokenIds[1], quantities[1], collector);
        vm.stopPrank();

        // 2. Setup unwrap call
        // setup mock receiver contract that will receive eith with some call
        MockReceiverContract mockReceiverContract = new MockReceiverContract();

        bytes memory mockReceiverCall = abi.encodeWithSelector(mockReceiverContract.mockReceiveFunction.selector, "randomArgument");

        // this is how much value will be forwarded to the receiver
        uint256 totalAmount = 2.6 ether;

        SponsoredMintBatch memory sponsoredMint = SponsoredMintBatch({
            verifier: verifier,
            from: collector,
            destination: payable(address(mockReceiverContract)),
            data: mockReceiverCall,
            totalAmount: 2.6 ether,
            expectedRedeemAmount: 2.5 ether,
            ids: tokenIds,
            quantities: quantities,
            nonce: 1,
            deadline: block.timestamp + 100
        });

        // encode call to call on the receiver
        bytes memory encodedCall = abi.encodeWithSelector(
            ISponsoredSparksSpenderAction.sponsoredMintBatch.selector,
            sponsoredMint,
            _signSponsoredMintAction(sponsoredMint, verifierPrivateKey)
        );

        // receiver should be called with the value to send, and the encoded call above
        vm.expectCall(address(mockReceiverContract), totalAmount, abi.encodeCall(mockReceiverContract.mockReceiveFunction, "randomArgument"));

        vm.prank(collector);
        sparks.safeBatchTransferFrom(collector, address(sponsoredSparksSpender), tokenIds, quantities, encodedCall);

        assertEq(address(mockReceiverContract).balance, totalAmount);
    }

    function test_sparksWrongRedeemAmount() external {
        // Fund Sponsored Sparks Spender
        sponsoredSparksSpender.fund{value: 10 ether}();

        // 1. Mint some eth based tokens
        uint256[] memory quantities = new uint256[](2);
        quantities[0] = 3;
        quantities[1] = 2;

        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 1;
        tokenIds[1] = 3;

        vm.deal(collector, 100 ether);

        vm.startPrank(collector);
        sparksManager.mintWithEth{value: 0.5 ether * quantities[0]}(1, quantities[0], collector);
        vm.stopPrank();

        vm.prank(admin);
        sparksManager.createToken(tokenIds[1], TokenConfig({price: 0.5 ether, tokenAddress: address(0), redeemHandler: address(0)}));

        vm.startPrank(collector);
        sparksManager.mintWithEth{value: 0.5 ether * quantities[1]}(tokenIds[1], quantities[1], collector);
        vm.stopPrank();

        // 2. Setup unwrap call
        // setup mock receiver contract that will receive eith with some call
        MockReceiverContract mockReceiverContract = new MockReceiverContract();

        bytes memory mockReceiverCall = abi.encodeWithSelector(mockReceiverContract.mockReceiveFunction.selector, "randomArgument");

        SponsoredMintBatch memory sponsoredMint = SponsoredMintBatch({
            verifier: verifier,
            from: collector,
            destination: payable(address(mockReceiverContract)),
            data: mockReceiverCall,
            totalAmount: 1.5 ether,
            expectedRedeemAmount: 1 ether,
            ids: tokenIds,
            quantities: quantities,
            nonce: 1,
            deadline: block.timestamp + 100
        });

        // encode call to call on the receiver
        bytes memory encodedCall = abi.encodeWithSelector(
            ISponsoredSparksSpenderAction.sponsoredMintBatch.selector,
            sponsoredMint,
            _signSponsoredMintAction(sponsoredMint, verifierPrivateKey)
        );

        vm.prank(collector);
        vm.expectRevert(abi.encodeWithSelector(ISponsoredSparksSpender.RedeemAmountIsIncorrect.selector, 1000000000000000000, 2500000000000000000));
        sparks.safeBatchTransferFrom(collector, address(sponsoredSparksSpender), tokenIds, quantities, encodedCall);
    }

    function test_sparksWithAdditionalValueUnwrapSingle() external {
        // Fund Sponsored Sparks Spender
        sponsoredSparksSpender.fund{value: 10 ether}();

        vm.deal(collector, 100 ether);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 1;

        uint256[] memory quantities = new uint256[](1);
        quantities[0] = 2;

        vm.startPrank(collector);
        sparksManager.mintWithEth{value: 0.5 ether * quantities[0]}(1, quantities[0], collector);
        vm.stopPrank();

        vm.prank(admin);
        sparksManager.createToken(3, TokenConfig({price: 0.5 ether, tokenAddress: address(0), redeemHandler: address(0)}));

        vm.startPrank(collector);
        sparksManager.mintWithEth{value: 0.5 ether * quantities[0]}(3, quantities[0], collector);
        vm.stopPrank();

        // 2. Setup unwrap call
        // setup mock receiver contract that will receive eith with some call
        MockReceiverContract mockReceiverContract = new MockReceiverContract();

        bytes memory mockReceiverCall = abi.encodeWithSelector(mockReceiverContract.mockReceiveFunction.selector, "randomArgument");

        uint256 totalAmount = 1.5 ether;

        SponsoredMintBatch memory sponsoredMint = SponsoredMintBatch({
            verifier: verifier,
            from: collector,
            destination: payable(address(mockReceiverContract)),
            data: mockReceiverCall,
            totalAmount: totalAmount,
            expectedRedeemAmount: 1 ether,
            ids: tokenIds,
            quantities: quantities,
            nonce: 1,
            deadline: block.timestamp + 100
        });

        // encode call to call on the receiver
        bytes memory encodedCall = abi.encodeWithSelector(
            ISponsoredSparksSpenderAction.sponsoredMintBatch.selector,
            sponsoredMint,
            _signSponsoredMintAction(sponsoredMint, verifierPrivateKey)
        );

        // receiver should be called with the value to send, and the encoded call above
        vm.expectCall(address(mockReceiverContract), totalAmount, abi.encodeCall(mockReceiverContract.mockReceiveFunction, "randomArgument"));

        vm.prank(collector);
        sparks.safeTransferFrom(collector, address(sponsoredSparksSpender), 1, 2, encodedCall);

        assertEq(address(mockReceiverContract).balance, totalAmount);
    }

    function test_spendFunctionInvalidSignature() external {
        sponsoredSparksSpender.fund{value: 10 ether}();

        MockReceiverContract mockReceiverContract = new MockReceiverContract();

        bytes memory mockReceiverCall = abi.encodeWithSelector(mockReceiverContract.mockReceiveFunction.selector, "randomArgument");

        SponsoredSpend memory sponsoredSpend = SponsoredSpend({
            verifier: verifier,
            from: address(collector),
            destination: payable(address(mockReceiverContract)),
            data: mockReceiverCall,
            totalAmount: 1.5 ether,
            expectedInputAmount: 1.258 ether,
            nonce: 1,
            deadline: block.timestamp
        });

        vm.deal(collector, 2 ether);
        vm.prank(collector);
        vm.expectRevert(abi.encodeWithSelector(ISponsoredSparksSpender.InvalidSignature.selector));
        sponsoredSparksSpender.sponsoredExecute{value: 1.258 ether}(sponsoredSpend, hex"cafecafe");
    }

    function test_spendFunctionWrongSpender() external {
        sponsoredSparksSpender.fund{value: 10 ether}();

        MockReceiverContract mockReceiverContract = new MockReceiverContract();

        bytes memory mockReceiverCall = abi.encodeWithSelector(mockReceiverContract.mockReceiveFunction.selector, "randomArgument");

        address badVerifier = makeAddr("badVerifier");

        SponsoredSpend memory sponsoredSpend = SponsoredSpend({
            verifier: badVerifier,
            from: address(0x1234),
            destination: payable(address(mockReceiverContract)),
            data: mockReceiverCall,
            totalAmount: 1.5 ether,
            expectedInputAmount: 1.258 ether,
            nonce: 1,
            deadline: block.timestamp + 100
        });

        bytes memory signature = _signSponsoredSpendAction(sponsoredSpend, verifierPrivateKey);

        vm.deal(collector, 2 ether);
        vm.prank(collector);
        vm.expectRevert(abi.encodeWithSelector(ISponsoredSparksSpender.VerifierNotAllowed.selector, badVerifier));
        sponsoredSparksSpender.sponsoredExecute{value: 1.258 ether}(sponsoredSpend, signature);
    }

    function test_spendFunctionExpiredSignature() external {
        sponsoredSparksSpender.fund{value: 10 ether}();

        MockReceiverContract mockReceiverContract = new MockReceiverContract();

        bytes memory mockReceiverCall = abi.encodeWithSelector(mockReceiverContract.mockReceiveFunction.selector, "randomArgument");

        SponsoredSpend memory sponsoredSpend = SponsoredSpend({
            verifier: verifier,
            from: collector,
            destination: payable(address(mockReceiverContract)),
            data: mockReceiverCall,
            totalAmount: 1.5 ether,
            expectedInputAmount: 1.258 ether,
            nonce: 1,
            deadline: 0
        });

        vm.warp(100);

        vm.deal(collector, 2 ether);

        bytes memory signature = _signSponsoredSpendAction(sponsoredSpend, verifierPrivateKey);

        vm.deal(collector, 2 ether);
        vm.expectRevert(ISponsoredSparksSpender.SignatureExpired.selector);
        vm.prank(collector);
        sponsoredSparksSpender.sponsoredExecute{value: 1.258 ether}(sponsoredSpend, signature);
    }

    function test_spendFunctionNonceUsed() external {
        sponsoredSparksSpender.fund{value: 10 ether}();

        MockReceiverContract mockReceiverContract = new MockReceiverContract();

        bytes memory mockReceiverCall = abi.encodeWithSelector(mockReceiverContract.mockReceiveFunction.selector, "randomArgument");

        SponsoredSpend memory sponsoredSpend = SponsoredSpend({
            verifier: verifier,
            from: collector,
            destination: payable(address(mockReceiverContract)),
            data: mockReceiverCall,
            totalAmount: 1.5 ether,
            expectedInputAmount: 1.258 ether,
            nonce: 1,
            deadline: block.timestamp + 100
        });

        bytes memory signature = _signSponsoredSpendAction(sponsoredSpend, verifierPrivateKey);

        vm.deal(collector, 4 ether);
        vm.startPrank(collector);
        sponsoredSparksSpender.sponsoredExecute{value: 1.258 ether}(sponsoredSpend, signature);

        vm.expectRevert(ISponsoredSparksSpender.NonceUsed.selector);
        sponsoredSparksSpender.sponsoredExecute{value: 1.258 ether}(sponsoredSpend, signature);
    }

    function test_spendFunctionDirectGoodCall() external {
        sponsoredSparksSpender.fund{value: 10 ether}();

        MockReceiverContract mockReceiverContract = new MockReceiverContract();

        bytes memory mockReceiverCall = abi.encodeWithSelector(mockReceiverContract.mockReceiveFunction.selector, "randomArgument");

        SponsoredSpend memory sponsoredSpend = SponsoredSpend({
            verifier: verifier,
            from: collector,
            destination: payable(address(mockReceiverContract)),
            data: mockReceiverCall,
            totalAmount: 1.5 ether,
            expectedInputAmount: 1.258 ether,
            nonce: 1,
            deadline: block.timestamp + 100
        });

        bytes memory signature = _signSponsoredSpendAction(sponsoredSpend, verifierPrivateKey);

        vm.deal(collector, 2 ether);
        vm.prank(collector);
        sponsoredSparksSpender.sponsoredExecute{value: 1.258 ether}(sponsoredSpend, signature);

        assertEq(mockReceiverContract.received(), true);
        assertEq(address(mockReceiverContract).balance, 1.5 ether);
    }

    function test_spendFunctionDirectBadCall() external {
        sponsoredSparksSpender.fund{value: 10 ether}();

        MockReceiverContract mockReceiverContract = new MockReceiverContract();

        bytes memory mockReceiverCall = abi.encode("whatever");

        SponsoredSpend memory sponsoredSpend = SponsoredSpend({
            verifier: verifier,
            from: collector,
            destination: payable(address(mockReceiverContract)),
            data: mockReceiverCall,
            totalAmount: 1.5 ether,
            expectedInputAmount: 1.258 ether,
            nonce: 1,
            deadline: block.timestamp + 100
        });

        bytes memory signature = _signSponsoredSpendAction(sponsoredSpend, verifierPrivateKey);

        vm.deal(collector, 2 ether);
        vm.prank(collector);
        // this is reverting because the function call whatever doesn't exist on the receiver contract

        vm.expectRevert(abi.encodeWithSelector(ISponsoredSparksSpender.CallFailed.selector, bytes("")));
        sponsoredSparksSpender.sponsoredExecute{value: 1.258 ether}(sponsoredSpend, signature);
    }

    function test_sparksWithBadCall() external {
        // Fund Sponsored Sparks Spender
        sponsoredSparksSpender.fund{value: 10 ether}();

        // 1. Mint some eth based tokens
        uint256[] memory quantities = new uint256[](1);
        quantities[0] = 3;

        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 1;
        tokenIds[1] = 3;

        vm.deal(collector, 100 ether);

        vm.startPrank(collector);
        sparksManager.mintWithEth{value: 0.5 ether * quantities[0]}(1, quantities[0], collector);
        vm.stopPrank();

        vm.prank(admin);
        sparksManager.createToken(tokenIds[1], TokenConfig({price: 0.5 ether, tokenAddress: address(0), redeemHandler: address(0)}));

        // 2. Setup unwrap call
        // setup mock receiver contract that will receive eith with some call
        MockReceiverContract mockReceiverContract = new MockReceiverContract();

        bytes memory mockReceiverCall = abi.encodeWithSelector(mockReceiverContract.mockReceiveFunction.selector, "randomArgument");

        SponsoredMintBatch memory sponsoredMint = SponsoredMintBatch({
            verifier: verifier,
            from: collector,
            destination: payable(address(mockReceiverContract)),
            data: mockReceiverCall,
            totalAmount: 1.5 ether,
            expectedRedeemAmount: 1.258 ether,
            ids: tokenIds,
            quantities: quantities,
            nonce: 1,
            deadline: block.timestamp + 100
        });

        // encode call to call on the receiver
        bytes memory encodedCall = abi.encodeWithSelector(
            ISponsoredSparksSpenderAction.sponsoredMintBatch.selector,
            sponsoredMint,
            _signSponsoredMintAction(sponsoredMint, verifierPrivateKey)
        );

        uint256[] memory quantitiesNew = new uint256[](2);
        quantitiesNew[0] = 1;
        quantitiesNew[1] = 0;

        vm.prank(collector);
        vm.expectRevert(ISponsoredSparksSpender.LengthMismatch.selector);
        sparks.safeBatchTransferFrom(collector, address(sponsoredSparksSpender), tokenIds, quantitiesNew, encodedCall);
    }

    function test_SponsoredSparksWithdrawFails() public {
        address(sponsoredSparksSpender).call{value: 1 ether}("");

        address nonPayableContract = address(new NonPayableContract());

        vm.prank(sponsoredSparksSpender.owner());
        sponsoredSparksSpender.transferOwnership(nonPayableContract);

        vm.prank(nonPayableContract);
        sponsoredSparksSpender.acceptOwnership();

        assertEq(sponsoredSparksSpender.owner(), nonPayableContract);

        vm.expectRevert(ISponsoredSparksSpender.WithdrawFailed.selector);
        vm.prank(nonPayableContract);
        sponsoredSparksSpender.withdraw(0);
    }

    function test_SponsoredSparksWithdraw() public {
        address(sponsoredSparksSpender).call{value: 1 ether}("");

        uint256 adminBalance = admin.balance;
        vm.prank(admin);
        sponsoredSparksSpender.withdraw(0);
        assertEq(admin.balance - adminBalance, 1 ether);

        assertEq(address(sponsoredSparksSpender).balance, 0);

        address(sponsoredSparksSpender).call{value: 1 ether}("");

        adminBalance = admin.balance;

        vm.prank(admin);
        sponsoredSparksSpender.withdraw(0.4 ether);

        assertEq(admin.balance - adminBalance, 0.4 ether);

        assertEq(address(sponsoredSparksSpender).balance, 0.6 ether);
    }

    function testNotCallingFromSparks() public {
        uint256[] memory ids = new uint256[](0);
        uint256[] memory quantities = new uint256[](0);

        vm.prank(collector);
        vm.expectRevert(ISponsoredSparksSpender.NotZoraSparks1155.selector);
        sponsoredSparksSpender.onERC1155BatchReceived(address(0), address(0), ids, quantities, hex"123456");
    }

    function testContractMetadata() public {
        assertEq(sponsoredSparksSpender.contractName(), "SponsoredSparksSpender");
        assertEq(sponsoredSparksSpender.contractVersion(), "2.0.0");
    }

    function testAttemptUnknownTransferAction() public {
        uint256[] memory ids = new uint256[](0);
        uint256[] memory quantities = new uint256[](0);

        vm.prank(address(sparks));
        vm.expectRevert();
        sponsoredSparksSpender.onERC1155BatchReceived(address(0), address(0), ids, quantities, hex"123456");
    }

    function _signSponsoredMintAction(SponsoredMintBatch memory sponsoredMint, uint256 privateKey) private view returns (bytes memory signature) {
        bytes32 digest = sponsoredSparksSpender.hashSponsoredMint(sponsoredMint);

        // create a signature with the digest for the params
        signature = _sign(privateKey, digest);
    }

    function _signSponsoredSpendAction(SponsoredSpend memory sponsoredSpend, uint256 privateKey) private view returns (bytes memory signature) {
        bytes32 digest = sponsoredSparksSpender.hashSponsoredSpend(sponsoredSpend);

        signature = _sign(privateKey, digest);
    }

    function _sign(uint256 privateKey, bytes32 digest) private pure returns (bytes memory) {
        // sign the message
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);

        // combine into a single bytes array
        return abi.encodePacked(r, s, v);
    }
}
