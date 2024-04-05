// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";

import {IZoraMints1155} from "../src/interfaces/IZoraMints1155.sol";
import {ZoraMints1155} from "../src/ZoraMints1155.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC1155Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {ReceiveRejector} from "@zoralabs/shared-contracts/mocks/ReceiveRejector.sol";
import {MockPreminter} from "./mocks/MockPreminter.sol";
import {IZoraCreator1155PremintExecutorV2} from "@zoralabs/shared-contracts/interfaces/IZoraCreator1155PremintExecutorV2.sol";
import {ContractCreationConfig, PremintConfigV2, TokenCreationConfigV2, MintArguments, PremintResult} from "@zoralabs/shared-contracts/entities/Premint.sol";
import {Mock1155, MockMinter1155, IMinter1155} from "./mocks/Mock1155.sol";
import {PremintEncoding, EncodedPremintConfig} from "@zoralabs/shared-contracts/premint/PremintEncoding.sol";
import {IMintWithMints} from "../src/IMintWithMints.sol";
import {ZoraMintsFixtures} from "./fixtures/ZoraMintsFixtures.sol";
import {TokenConfig} from "../src/ZoraMintsTypes.sol";
import {ZoraMintsManagerImpl} from "../src/ZoraMintsManagerImpl.sol";
import {ICollectWithZoraMints} from "../src/ICollectWithZoraMints.sol";
import {MintsCaller} from "../src/utils/MintsCaller.sol";
import {UnorderedNonces} from "../src/utils/UnorderedNonces.sol";
import {IZoraMints1155Managed} from "../src/interfaces/IZoraMints1155Managed.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";

contract ERC1271WalletMock is Ownable, IERC1271 {
    constructor(address originalOwner) Ownable(originalOwner) {}

    function isValidSignature(bytes32 hash, bytes memory signature) public view returns (bytes4 magicValue) {
        return ECDSA.recover(hash, signature) == owner() ? this.isValidSignature.selector : bytes4(0);
    }

    bytes4 constant ON_ERC1155_RECEIVED_HASH = IERC1155Receiver.onERC1155Received.selector;
    bytes4 constant ON_ERC1155_BATCH_RECEIVED_HASH = IERC1155Receiver.onERC1155BatchReceived.selector;

    // /// Allows receiving ERC1155 tokens
    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external pure returns (bytes4) {
        return ON_ERC1155_RECEIVED_HASH;
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata) external pure returns (bytes4) {
        return ON_ERC1155_BATCH_RECEIVED_HASH;
    }
}

contract ZoraMints1155Test is Test {
    address admin = makeAddr("admin");
    address proxyAdmin = makeAddr("proxyAdmin");
    address collector;
    uint256 collectorPrivateKey;

    ZoraMints1155 mints;

    uint256 initialTokenId = 995;
    uint256 initialTokenPrice = 4.32 ether;

    Mock1155 mock1155;

    uint256 globalNonce = 0;

    IMinter1155 mockMinter;
    MockPreminter mockPreminter;

    ContractCreationConfig contractCreationConfig;

    TokenCreationConfigV2 tokenCreationConfig;

    PremintConfigV2 premintConfig;

    MintArguments mintArguments;

    address signerContract = makeAddr("signerContract");

    ZoraMintsManagerImpl mintsManager;

    function setUp() external {
        (collector, collectorPrivateKey) = makeAddrAndKey("collector");
        (mockPreminter, mints, mintsManager) = ZoraMintsFixtures.setupMintsProxyWithMockPreminter(proxyAdmin, admin, initialTokenId, initialTokenPrice);
        mock1155 = new Mock1155(mintsManager, address(0), "", "");
        mockMinter = new MockMinter1155();

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

        premintConfig = PremintConfigV2({tokenConfig: tokenCreationConfig, uid: 0, version: 0, deleted: false});

        mintArguments = MintArguments({mintRecipient: makeAddr("mintRecipient"), mintComment: "mintComment", mintRewardsRecipients: new address[](0)});
    }

    function makeEthTokenConfig(uint256 pricePerToken) internal pure returns (TokenConfig memory) {
        return TokenConfig({price: pricePerToken, tokenAddress: address(0), redeemHandler: address(0)});
    }

    function createEthToken(uint256 tokenId, uint256 pricePerToken, bool defaultMintable) internal {
        mintsManager.createToken(tokenId, makeEthTokenConfig(pricePerToken), defaultMintable);
    }

    function setMintableEthToken(uint256 tokenId) internal {
        mintsManager.setDefaultMintable(address(0), tokenId);
    }

    function setupTokenIds(uint256[] memory tokenIds, uint256[] memory tokenPrices) private {
        for (uint i = 0; i < tokenIds.length; i++) {
            vm.prank(admin);
            createEthToken(tokenIds[i], uint96(tokenPrices[i]), true);
        }
    }

    function setupTokenIds(uint256[] memory tokenIds) private {
        uint256[] memory tokenPrices = new uint256[](tokenIds.length);
        for (uint i = 0; i < tokenIds.length; i++) {
            tokenPrices[i] = 1 ether;
        }

        setupTokenIds(tokenIds, tokenPrices);
    }

    function mintQuantities(address minter, uint256[] memory tokenIds, uint256[] memory quantities) private {
        for (uint i = 0; i < tokenIds.length; i++) {
            vm.prank(admin);
            setMintableEthToken(tokenIds[i]);
            vm.deal(minter, mintsManager.getEthPrice() * quantities[i]);
            mintsManager.mintWithEth{value: mintsManager.getEthPrice() * quantities[i]}(quantities[i], minter);
        }
    }

    function collectPremintV2(
        uint256 value,
        uint256[] memory tokenIds,
        uint256[] memory quantities,
        ContractCreationConfig memory contractConfig,
        PremintConfigV2 memory _premintConfig,
        bytes memory signature,
        MintArguments memory _mintArguments,
        address _signerContract
    ) public payable {
        bytes memory call = abi.encodeWithSelector(
            ICollectWithZoraMints.collectPremintV2.selector,
            contractConfig,
            _premintConfig,
            signature,
            _mintArguments,
            _signerContract
        );
        ZoraMints1155(address(mints)).transferBatchToManagerAndCall{value: value}(tokenIds, quantities, call);
    }

    function test_collect_revertsWhen_invalid_balance() external {
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 2;
        tokenIds[1] = 3;

        setupTokenIds(tokenIds);

        uint256[] memory quantities = new uint256[](2);

        // have collector collect 3 mints of current token id
        quantities[0] = 2;
        quantities[1] = 3;

        mintQuantities(collector, tokenIds, quantities);

        // try to collect with more quantities then owned
        quantities[1] = quantities[1] + 1;

        vm.prank(collector);
        vm.expectRevert(abi.encodeWithSelector(IERC1155Errors.ERC1155InsufficientBalance.selector, collector, 3, quantities[1], tokenIds[1]));
        MintsCaller.collect(
            mints,
            0,
            tokenIds,
            quantities,
            mock1155,
            mockMinter,
            1,
            mintArguments.mintRewardsRecipients,
            mintArguments.mintRecipient,
            mintArguments.mintComment
        );
    }

    function test_collect_transfers_balance_to_receipient_1155_contracts(uint8 quantity1, uint8 quantity2) external {
        vm.assume(quantity1 > 0);
        vm.assume(quantity2 > 0);

        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 2;
        tokenIds[1] = 3;

        setupTokenIds(tokenIds);

        uint256[] memory quantities = new uint256[](2);
        quantities[0] = quantity1;
        quantities[1] = quantity2;
        mintQuantities(collector, tokenIds, quantities);

        assertEq(mints.balanceOfAccount(collector), uint256(quantity1) + uint256(quantity2));

        // collect with proper amount; ensure that the tokens have been transferred to the 1155 contract
        vm.prank(collector);
        MintsCaller.collect(
            mints,
            0,
            tokenIds,
            quantities,
            mock1155,
            mockMinter,
            1,
            mintArguments.mintRewardsRecipients,
            mintArguments.mintRecipient,
            mintArguments.mintComment
        );

        assertEq(mints.balanceOfAccount(collector), 0);

        for (uint i = 0; i < tokenIds.length; i++) {
            // ensure that the collector no longer has the tokens
            assertEq(mints.balanceOf(collector, tokenIds[i]), 0);
            // ensure that the 1155 contract has the tokens
            assertEq(mints.balanceOf(address(mock1155), tokenIds[i]), quantities[i]);
        }

        assertEq(mints.balanceOfAccount(collector), 0);
    }

    function test_collects_calls_1155_mintWithMints(uint16 valueToSend) external {
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 2;
        tokenIds[1] = 3;

        setupTokenIds(tokenIds);

        uint256[] memory quantities = new uint256[](2);
        quantities[0] = 5;
        quantities[1] = 3;
        mintQuantities(collector, tokenIds, quantities);

        uint256 tokenId = 5;

        address[] memory rewardsRecipients = new address[](2);
        rewardsRecipients[0] = makeAddr("rewardsRecipient1");
        rewardsRecipients[1] = makeAddr("rewardsRecipient2");

        mintArguments.mintRewardsRecipients = rewardsRecipients;

        vm.expectCall(
            address(mock1155),
            valueToSend,
            abi.encodeCall(mock1155.mintWithMints, (tokenIds, quantities, mockMinter, tokenId, rewardsRecipients, abi.encode(mintArguments.mintRecipient, "")))
        );

        vm.deal(collector, valueToSend);
        vm.prank(collector);
        MintsCaller.collect(
            mints,
            valueToSend,
            tokenIds,
            quantities,
            mock1155,
            mockMinter,
            tokenId,
            mintArguments.mintRewardsRecipients,
            mintArguments.mintRecipient,
            mintArguments.mintComment
        );
    }

    event MintComment(address indexed sender, address indexed tokenContract, uint256 indexed tokenId, uint256 quantity, string comment);

    function test_collects_withComment_emitsMintComment(uint16 valueToSend) external {
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 2;

        setupTokenIds(tokenIds);

        uint256[] memory quantities = new uint256[](1);
        quantities[0] = 7;
        mintQuantities(collector, tokenIds, quantities);

        uint256 tokenId = 5;

        address[] memory rewardsRecipients = new address[](2);
        rewardsRecipients[0] = makeAddr("rewardsRecipient1");
        rewardsRecipients[1] = makeAddr("rewardsRecipient2");

        mintArguments.mintComment = "comment!";
        mintArguments.mintRewardsRecipients = rewardsRecipients;

        bytes memory expectedMintArguments = abi.encode(mintArguments.mintRecipient, "");

        vm.expectCall(
            address(mock1155),
            valueToSend,
            abi.encodeCall(mock1155.mintWithMints, (tokenIds, quantities, mockMinter, tokenId, rewardsRecipients, expectedMintArguments))
        );

        vm.expectEmit(true, true, true, true);

        emit MintComment(collector, address(mock1155), tokenId, 7, mintArguments.mintComment);

        vm.deal(collector, valueToSend);
        vm.prank(collector);
        MintsCaller.collect(
            mints,
            valueToSend,
            tokenIds,
            quantities,
            mock1155,
            mockMinter,
            tokenId,
            mintArguments.mintRewardsRecipients,
            mintArguments.mintRecipient,
            mintArguments.mintComment
        );
    }

    function test_collects_withOutMintComment_forwardsMinterArguments() external {
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 2;

        setupTokenIds(tokenIds);

        uint256[] memory quantities = new uint256[](1);
        quantities[0] = 7;
        mintQuantities(collector, tokenIds, quantities);

        address[] memory rewardsRecipients = new address[](0);

        uint256 tokenId = 8;

        string memory mintComment = "comment!!";

        // make abnormally shaped mint arguments.
        bytes memory minterArguments = abi.encode(makeAddr("someAddress"), "something random", 123456, "something else");

        ICollectWithZoraMints.CollectMintArguments memory _mintArguments = ICollectWithZoraMints.CollectMintArguments({
            minterArguments: minterArguments,
            mintComment: mintComment,
            mintRewardsRecipients: rewardsRecipients
        });

        bytes memory call = abi.encodeWithSelector(ICollectWithZoraMints.collect.selector, mock1155, mockMinter, tokenId, _mintArguments);

        vm.expectCall(
            address(mock1155),
            0,
            abi.encodeCall(mock1155.mintWithMints, (tokenIds, quantities, mockMinter, tokenId, rewardsRecipients, minterArguments))
        );

        vm.prank(collector);
        mints.transferBatchToManagerAndCall(tokenIds, quantities, call);
    }

    event Collected(uint256[] indexed tokenIds, uint256[] quantities, address indexed zoraCreator1155Contract, uint256 indexed zoraCreator1155TokenId);

    function test_collect_emits_collected() external {
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 2;
        tokenIds[1] = 3;

        setupTokenIds(tokenIds);

        uint256[] memory quantities = new uint256[](2);
        quantities[0] = 5;
        quantities[1] = 3;
        mintQuantities(collector, tokenIds, quantities);

        uint256 tokenId = 5;

        vm.expectEmit(true, true, true, true);
        emit Collected(tokenIds, quantities, address(mock1155), tokenId);

        vm.prank(collector);
        MintsCaller.collect(
            mints,
            0,
            tokenIds,
            quantities,
            mock1155,
            mockMinter,
            tokenId,
            mintArguments.mintRewardsRecipients,
            mintArguments.mintRecipient,
            mintArguments.mintComment
        );
    }

    function test_premint_contractNotCreatedYet_transfers_balance_to_predicted_1155_contract(uint8 quantity1, uint8 quantity2) external {
        vm.assume(quantity1 > 0);
        vm.assume(quantity2 > 0);

        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 2;
        tokenIds[1] = 3;

        setupTokenIds(tokenIds);

        assertEq(mints.balanceOfAccount(collector), 0);

        uint256[] memory quantities = new uint256[](2);
        quantities[0] = quantity1;
        quantities[1] = quantity2;
        mintQuantities(collector, tokenIds, quantities);

        address expectedContractAddress = mockPreminter.getContractAddress(contractCreationConfig);

        assertEq(mints.balanceOfAccount(expectedContractAddress), 0);

        // we know the contract hasn't been created yet - lets verify that
        assertEq(expectedContractAddress.code.length, 0);

        bytes memory signature = bytes("hi!");

        // collect with proper amount; ensure that the tokens have been transferred to the predicted contract address
        vm.prank(collector);

        collectPremintV2(0, tokenIds, quantities, contractCreationConfig, premintConfig, signature, mintArguments, signerContract);

        // lets verify the contract has been created by making sure the code has size
        assertGt(expectedContractAddress.code.length, 0);

        for (uint i = 0; i < tokenIds.length; i++) {
            // ensure that the collector no longer has the tokens
            assertEq(mints.balanceOf(collector, tokenIds[i]), 0);
            // ensure that the 1155 contract has the tokens
            assertEq(mints.balanceOf(expectedContractAddress, tokenIds[i]), quantities[i]);
        }
        assertEq(mints.balanceOfAccount(expectedContractAddress), uint256(quantity1) + uint256(quantity2));
        assertEq(mints.balanceOfAccount(collector), 0);
    }

    function test_collectPremint_calls_premintWithMints() external {
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 2;
        tokenIds[1] = 3;

        setupTokenIds(tokenIds);

        uint256[] memory quantities = new uint256[](2);
        quantities[0] = 5;
        quantities[1] = 3;
        mintQuantities(collector, tokenIds, quantities);

        address[] memory rewardsRecipients = new address[](2);
        rewardsRecipients[0] = makeAddr("rewardsRecipient1");
        rewardsRecipients[1] = makeAddr("rewardsRecipient2");

        MintArguments memory emptyMintArguments;

        bytes memory signature = bytes("hi!");

        vm.prank(collector);
        vm.expectCall(
            address(mockPreminter),
            abi.encodeCall(
                mockPreminter.premintV2WithSignerContract,
                (contractCreationConfig, premintConfig, signature, 0, emptyMintArguments, collector, signerContract)
            )
        );

        collectPremintV2(0, tokenIds, quantities, contractCreationConfig, premintConfig, signature, mintArguments, signerContract);
    }

    function test_collectPremint_calls_mintWithMints() external {
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 2;
        tokenIds[1] = 3;

        setupTokenIds(tokenIds);

        uint256[] memory quantities = new uint256[](2);
        quantities[0] = 5;
        quantities[1] = 3;
        mintQuantities(collector, tokenIds, quantities);

        address[] memory rewardsRecipients = new address[](2);
        rewardsRecipients[0] = makeAddr("rewardsRecipient1");
        rewardsRecipients[1] = makeAddr("rewardsRecipient2");

        address contractAddress = mockPreminter.getContractAddress(contractCreationConfig);

        uint256 expectedTokenId = mockPreminter.predictedTokenId();

        bytes memory signature = "";

        vm.expectCall(
            contractAddress,
            abi.encodeCall(
                IMintWithMints(contractAddress).mintWithMints,
                (
                    tokenIds,
                    quantities,
                    IMinter1155(premintConfig.tokenConfig.fixedPriceMinter),
                    expectedTokenId,
                    mintArguments.mintRewardsRecipients,
                    abi.encode(mintArguments.mintRecipient, "")
                )
            )
        );

        vm.prank(collector);
        collectPremintV2(0, tokenIds, quantities, contractCreationConfig, premintConfig, signature, mintArguments, signerContract);
    }

    function test_collectPremint_emits_collected() external {
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 2;
        tokenIds[1] = 3;

        setupTokenIds(tokenIds);

        uint256[] memory quantities = new uint256[](2);
        quantities[0] = 5;
        quantities[1] = 3;
        mintQuantities(collector, tokenIds, quantities);

        address[] memory rewardsRecipients = new address[](2);
        rewardsRecipients[0] = makeAddr("rewardsRecipient1");
        rewardsRecipients[1] = makeAddr("rewardsRecipient2");

        bytes memory signature = bytes("hi!");

        // we do this hacky trick where we can predict the token id based on the mock
        uint256 expectedTokenId = mockPreminter.predictedTokenId();

        vm.expectEmit(true, true, true, true);
        emit Collected(tokenIds, quantities, mockPreminter.getContractAddress(contractCreationConfig), expectedTokenId);
        vm.prank(collector);
        collectPremintV2(0, tokenIds, quantities, contractCreationConfig, premintConfig, signature, mintArguments, signerContract);
    }

    function _makeValidCollectCall() private view returns (bytes memory) {
        uint256 tokenIdToCollect = 1;
        return
            MintsCaller.makeCollectCall(
                mock1155,
                mockMinter,
                tokenIdToCollect,
                mintArguments.mintRewardsRecipients,
                mintArguments.mintRecipient,
                mintArguments.mintComment
            );
    }

    function test_permitSafeTransferBatch_whenEOA_canCollect() external {
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 2;
        tokenIds[1] = 3;

        setupTokenIds(tokenIds);

        uint256[] memory quantities = new uint256[](2);
        quantities[0] = 5;
        quantities[1] = 3;
        mintQuantities(collector, tokenIds, quantities);

        IZoraMints1155Managed.PermitBatch memory permit = IZoraMints1155Managed.PermitBatch({
            owner: collector,
            to: address(mintsManager),
            tokenIds: tokenIds,
            quantities: quantities,
            safeTransferData: _makeValidCollectCall(),
            deadline: block.timestamp + 100,
            nonce: globalNonce++
        });

        bytes memory signature = _signPermit(permit, collectorPrivateKey);

        mints.permitSafeTransferBatch(permit, signature);

        assertEq(mints.balanceOfAccount(address(mock1155)), uint256(quantities[0]) + uint256(quantities[1]));
        assertEq(mints.balanceOfAccount(collector), 0);
    }

    function test_permitSafeTransferSingle_whenEOA_canCollect() external {
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 2;

        setupTokenIds(tokenIds);

        uint256[] memory quantities = new uint256[](1);
        quantities[0] = 5;
        mintQuantities(collector, tokenIds, quantities);

        IZoraMints1155Managed.PermitSingle memory permit = IZoraMints1155Managed.PermitSingle({
            owner: collector,
            to: address(mintsManager),
            tokenId: tokenIds[0],
            quantity: quantities[0],
            safeTransferData: _makeValidCollectCall(),
            deadline: block.timestamp + 100,
            nonce: globalNonce++
        });

        bytes memory signature = _signPermitSingle(permit, collectorPrivateKey);

        mints.permitSafeTransfer(permit, signature);

        assertEq(mints.balanceOfAccount(address(mock1155)), uint256(quantities[0]));
        assertEq(mints.balanceOfAccount(collector), 0);
    }

    function test_permitSafeTransferBatch_emitsMintCommentFromSigner() external {
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 2;
        tokenIds[1] = 3;

        setupTokenIds(tokenIds);

        uint256[] memory quantities = new uint256[](2);
        quantities[0] = 5;
        quantities[1] = 3;
        mintQuantities(collector, tokenIds, quantities);

        uint256 tokenIdToCollect = 1;

        IZoraMints1155Managed.PermitBatch memory permit = IZoraMints1155Managed.PermitBatch({
            owner: collector,
            to: address(mintsManager),
            tokenIds: tokenIds,
            quantities: quantities,
            safeTransferData: _makeValidCollectCall(),
            deadline: block.timestamp + 100,
            nonce: globalNonce++
        });

        bytes memory signature = _signPermit(permit, collectorPrivateKey);

        vm.expectEmit(true, true, true, true);

        emit MintComment(collector, address(mock1155), tokenIdToCollect, 8, mintArguments.mintComment);

        mints.permitSafeTransferBatch(permit, signature);
    }

    function test_permitSafeTransferSingle_emitsMintCommentFromSigner() external {
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 1;

        setupTokenIds(tokenIds);

        uint256[] memory quantities = new uint256[](2);
        quantities[0] = 8;
        mintQuantities(collector, tokenIds, quantities);

        uint256 tokenIdToCollect = 1;

        IZoraMints1155Managed.PermitSingle memory permit = IZoraMints1155Managed.PermitSingle({
            owner: collector,
            to: address(mintsManager),
            tokenId: tokenIds[0],
            quantity: quantities[0],
            safeTransferData: _makeValidCollectCall(),
            deadline: block.timestamp + 100,
            nonce: globalNonce++
        });

        bytes memory signature = _signPermitSingle(permit, collectorPrivateKey);

        vm.expectEmit(true, true, true, true);

        emit MintComment(collector, address(mock1155), tokenIdToCollect, 8, mintArguments.mintComment);

        mints.permitSafeTransfer(permit, signature);
    }

    function test_permitSafeTransferBatch_whenEOA_revertsWhen_invalidSignature() external {
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 2;

        setupTokenIds(tokenIds);

        uint256[] memory quantities = new uint256[](1);
        quantities[0] = 5;
        mintQuantities(collector, tokenIds, quantities);

        IZoraMints1155Managed.PermitBatch memory permit = IZoraMints1155Managed.PermitBatch({
            owner: collector,
            to: address(mintsManager),
            tokenIds: tokenIds,
            quantities: quantities,
            safeTransferData: "",
            deadline: block.timestamp + 100,
            nonce: globalNonce++
        });

        (, uint256 anotherPrivateKey) = makeAddrAndKey("anotherPrivateKey");

        bytes memory signature = _signPermit(permit, anotherPrivateKey);

        vm.expectRevert(IZoraMints1155Managed.InvalidSignature.selector);
        mints.permitSafeTransferBatch(permit, signature);
    }

    function test_permitSafeTransferSingle_whenEOA_revertsWhen_invalidSignature() external {
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 2;

        setupTokenIds(tokenIds);

        uint256[] memory quantities = new uint256[](1);
        quantities[0] = 5;
        mintQuantities(collector, tokenIds, quantities);

        IZoraMints1155Managed.PermitSingle memory permit = IZoraMints1155Managed.PermitSingle({
            owner: collector,
            to: address(mintsManager),
            tokenId: tokenIds[0],
            quantity: quantities[0],
            safeTransferData: "",
            deadline: block.timestamp + 100,
            nonce: globalNonce++
        });

        (, uint256 anotherPrivateKey) = makeAddrAndKey("anotherPrivateKey");

        bytes memory signature = _signPermitSingle(permit, anotherPrivateKey);

        vm.expectRevert(IZoraMints1155Managed.InvalidSignature.selector);
        mints.permitSafeTransfer(permit, signature);
    }

    function test_permitSafeTransferBatch_whenEOA_revertsWhen_signatureAlreadyUsed() external {
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 2;

        setupTokenIds(tokenIds);

        uint256[] memory quantities = new uint256[](1);
        quantities[0] = 5;
        mintQuantities(collector, tokenIds, quantities);

        uint256 tokenIdToCollect = 1;

        IZoraMints1155Managed.PermitBatch memory permit = IZoraMints1155Managed.PermitBatch({
            owner: collector,
            to: address(mintsManager),
            tokenIds: tokenIds,
            quantities: quantities,
            safeTransferData: _makeValidCollectCall(),
            deadline: block.timestamp + 100,
            nonce: globalNonce++
        });

        // collect not full amount, so we can call again
        permit.quantities[0] = 3;

        bytes memory signature = _signPermit(permit, collectorPrivateKey);

        mints.permitSafeTransferBatch(permit, signature);
        vm.expectRevert(abi.encodeWithSelector(UnorderedNonces.InvalidAccountNonce.selector, collector, 0));
        mints.permitSafeTransferBatch(permit, signature);

        // collect more with a new signature, it should pass
        permit.quantities[0] = 2;

        // sign again with new nonce
        permit.nonce = globalNonce++;
        signature = _signPermit(permit, collectorPrivateKey);
        mints.permitSafeTransferBatch(permit, signature);
    }

    function test_permitSafeTransferSingle_whenEOA_revertsWhen_signatureAlreadyUsed() external {
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 2;

        setupTokenIds(tokenIds);

        uint256[] memory quantities = new uint256[](1);
        quantities[0] = 5;
        mintQuantities(collector, tokenIds, quantities);

        uint256 tokenIdToCollect = 1;

        IZoraMints1155Managed.PermitSingle memory permit = IZoraMints1155Managed.PermitSingle({
            owner: collector,
            to: address(mintsManager),
            tokenId: tokenIds[0],
            quantity: quantities[0],
            safeTransferData: _makeValidCollectCall(),
            deadline: block.timestamp + 100,
            nonce: globalNonce++
        });

        // collect not full amount, so we can call again
        permit.quantity = 3;

        bytes memory signature = _signPermitSingle(permit, collectorPrivateKey);

        mints.permitSafeTransfer(permit, signature);
        vm.expectRevert(abi.encodeWithSelector(UnorderedNonces.InvalidAccountNonce.selector, collector, 0));
        mints.permitSafeTransfer(permit, signature);

        // collect more with a new signature, it should pass
        permit.quantity = 2;
        permit.nonce = globalNonce++;

        // sign again with new nonce
        signature = _signPermitSingle(permit, collectorPrivateKey);
        mints.permitSafeTransfer(permit, signature);
    }

    function test_permitSafeTransferBatch_whenEOA_revertsWhen_deadlineExpired() external {
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 2;

        setupTokenIds(tokenIds);

        uint256[] memory quantities = new uint256[](1);
        quantities[0] = 5;
        mintQuantities(collector, tokenIds, quantities);

        IZoraMints1155Managed.PermitBatch memory permit = IZoraMints1155Managed.PermitBatch({
            owner: collector,
            to: address(mintsManager),
            tokenIds: tokenIds,
            quantities: quantities,
            safeTransferData: "",
            deadline: block.timestamp - 1,
            nonce: globalNonce++
        });

        bytes memory signature = _signPermit(permit, collectorPrivateKey);

        vm.expectRevert(abi.encodeWithSelector(IZoraMints1155Managed.ERC2612ExpiredSignature.selector, block.timestamp));
        mints.permitSafeTransferBatch(permit, signature);
    }

    function test_permitSafeTransferSingle_whenEOA_revertsWhen_deadlineExpired() external {
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 2;

        setupTokenIds(tokenIds);

        uint256[] memory quantities = new uint256[](1);
        quantities[0] = 5;
        mintQuantities(collector, tokenIds, quantities);

        IZoraMints1155Managed.PermitSingle memory permit = IZoraMints1155Managed.PermitSingle({
            owner: collector,
            to: address(mintsManager),
            tokenId: tokenIds[0],
            quantity: quantities[0],
            safeTransferData: "",
            deadline: block.timestamp - 1,
            nonce: globalNonce++
        });

        bytes memory signature = _signPermitSingle(permit, collectorPrivateKey);

        vm.expectRevert(abi.encodeWithSelector(IZoraMints1155Managed.ERC2612ExpiredSignature.selector, block.timestamp));
        mints.permitSafeTransfer(permit, signature);
    }

    function test_permitSafeTransferBatch_whenContract_canCollect() external {
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 2;

        setupTokenIds(tokenIds);

        ERC1271WalletMock walletMock = new ERC1271WalletMock(collector);

        uint256[] memory quantities = new uint256[](1);
        quantities[0] = 5;
        mintQuantities(address(walletMock), tokenIds, quantities);

        IZoraMints1155Managed.PermitBatch memory permit = IZoraMints1155Managed.PermitBatch({
            // smart contract wallet is the once that is to be the permit signer
            owner: address(walletMock),
            to: address(mintsManager),
            tokenIds: tokenIds,
            quantities: quantities,
            safeTransferData: _makeValidCollectCall(),
            deadline: block.timestamp + 100,
            nonce: globalNonce++
        });

        // smart contract wallet is the once that is to be the permit signer
        bytes memory signature = _signPermit(permit, collectorPrivateKey);

        mints.permitSafeTransferBatch(permit, signature);

        assertEq(mints.balanceOfAccount(address(mock1155)), uint256(quantities[0]));
        assertEq(mints.balanceOfAccount(address(walletMock)), 0);
    }

    function test_permitSafeTransferSingle_whenContract_canCollect() external {
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 2;

        setupTokenIds(tokenIds);

        ERC1271WalletMock walletMock = new ERC1271WalletMock(collector);

        uint256[] memory quantities = new uint256[](1);
        quantities[0] = 5;
        mintQuantities(address(walletMock), tokenIds, quantities);

        IZoraMints1155Managed.PermitSingle memory permit = IZoraMints1155Managed.PermitSingle({
            // smart contract wallet is the once that is to be the permit signer
            owner: address(walletMock),
            to: address(mintsManager),
            tokenId: tokenIds[0],
            quantity: quantities[0],
            safeTransferData: _makeValidCollectCall(),
            deadline: block.timestamp + 100,
            nonce: globalNonce++
        });

        // smart contract wallet is the once that is to be the permit signer
        bytes memory signature = _signPermitSingle(permit, collectorPrivateKey);

        mints.permitSafeTransfer(permit, signature);

        assertEq(mints.balanceOfAccount(address(mock1155)), uint256(quantities[0]));
        assertEq(mints.balanceOfAccount(address(walletMock)), 0);
    }

    function test_permitSafeTransferBatch_whenContract_revertsWhen_nonContractSigner() external {
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 2;

        setupTokenIds(tokenIds);

        // make wallet mock, with another address as the owner
        ERC1271WalletMock walletMock = new ERC1271WalletMock(makeAddr("anotherOwner"));

        uint256[] memory quantities = new uint256[](1);
        quantities[0] = 5;
        mintQuantities(address(walletMock), tokenIds, quantities);

        IZoraMints1155Managed.PermitBatch memory permit = IZoraMints1155Managed.PermitBatch({
            // smart contract wallet is the once that is to be the permit signer
            owner: address(walletMock),
            to: address(mintsManager),
            tokenIds: tokenIds,
            quantities: quantities,
            safeTransferData: "",
            deadline: block.timestamp + 100,
            nonce: globalNonce++
        });

        // smart contract wallet is the once that is to be the permit signer
        bytes memory signature = _signPermit(permit, collectorPrivateKey);

        vm.expectRevert(IZoraMints1155Managed.InvalidSignature.selector);
        mints.permitSafeTransferBatch(permit, signature);
    }

    function test_permitSafeTransferSingle_whenContract_revertsWhen_nonContractSigner() external {
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 2;

        setupTokenIds(tokenIds);

        // make wallet mock, with another address as the owner
        ERC1271WalletMock walletMock = new ERC1271WalletMock(makeAddr("anotherOwner"));

        uint256[] memory quantities = new uint256[](1);
        quantities[0] = 5;
        mintQuantities(address(walletMock), tokenIds, quantities);

        IZoraMints1155Managed.PermitSingle memory permit = IZoraMints1155Managed.PermitSingle({
            // smart contract wallet is the once that is to be the permit signer
            owner: address(walletMock),
            to: address(mintsManager),
            tokenId: tokenIds[0],
            quantity: quantities[0],
            safeTransferData: "",
            deadline: block.timestamp + 100,
            nonce: globalNonce++
        });

        // smart contract wallet is the once that is to be the permit signer
        bytes memory signature = _signPermitSingle(permit, collectorPrivateKey);

        vm.expectRevert(IZoraMints1155Managed.InvalidSignature.selector);
        mints.permitSafeTransfer(permit, signature);
    }

    function _signPermit(IZoraMints1155Managed.PermitBatch memory permit, uint256 privateKey) private view returns (bytes memory signature) {
        bytes32 digest = mints.hashPermitBatch(permit);

        // create a signature with the digest for the params
        signature = _sign(privateKey, digest);
    }

    function _signPermitSingle(IZoraMints1155Managed.PermitSingle memory permit, uint256 privateKey) private view returns (bytes memory signature) {
        bytes32 digest = mints.hashPermitSingle(permit);

        // create a signature with the digest for the params
        signature = _sign(privateKey, digest);
    }

    function _sign(uint256 privateKey, bytes32 digest) private pure returns (bytes memory) {
        // sign the message
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);

        // combine into a single bytes array
        return abi.encodePacked(r, s, v);
    }
}
