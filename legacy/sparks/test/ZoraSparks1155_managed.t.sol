// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";

import {IZoraSparks1155} from "../src/interfaces/IZoraSparks1155.sol";
import {ZoraSparks1155} from "../src/ZoraSparks1155.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC1155Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {ReceiveRejector} from "@zoralabs/shared-contracts/mocks/ReceiveRejector.sol";
import {IZoraCreator1155PremintExecutorV2} from "@zoralabs/shared-contracts/interfaces/IZoraCreator1155PremintExecutorV2.sol";
import {ContractWithAdditionalAdminsCreationConfig, ContractCreationConfig, PremintConfigV2, TokenCreationConfigV2, MintArguments, PremintResult} from "@zoralabs/shared-contracts/entities/Premint.sol";
import {PremintEncoding} from "@zoralabs/shared-contracts/premint/PremintEncoding.sol";
import {ZoraSparksFixtures} from "./fixtures/ZoraSparksFixtures.sol";
import {TokenConfig} from "../src/ZoraSparksTypes.sol";
import {ZoraSparksManagerImpl} from "../src/ZoraSparksManagerImpl.sol";
import {UnorderedNonces} from "../src/utils/UnorderedNonces.sol";
import {IZoraSparks1155Managed} from "../src/interfaces/IZoraSparks1155Managed.sol";
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

contract ZoraSparks1155Test is Test {
    address admin = makeAddr("admin");
    address proxyAdmin = makeAddr("proxyAdmin");
    address collector;
    uint256 collectorPrivateKey;

    ZoraSparks1155 sparks;

    uint256 initialTokenId = 995;
    uint256 initialTokenPrice = 4.32 ether;

    uint256 globalNonce = 0;

    ContractWithAdditionalAdminsCreationConfig contractCreationConfig;

    TokenCreationConfigV2 tokenCreationConfig;

    PremintConfigV2 premintConfig;

    MintArguments mintArguments;

    address[] additionalPremintAdmins;
    address signerContract = makeAddr("signerContract");

    ZoraSparksManagerImpl sparksManager;

    address operator = makeAddr("operator");

    function setUp() external {
        (collector, collectorPrivateKey) = makeAddrAndKey("collector");
        (sparks, sparksManager) = ZoraSparksFixtures.setupSparksProxyWithMockPreminter(proxyAdmin, admin, initialTokenId, initialTokenPrice);

        additionalPremintAdmins = new address[](1);
        additionalPremintAdmins[0] = makeAddr("additionalPremintAdmin");
        contractCreationConfig = ContractWithAdditionalAdminsCreationConfig({
            contractAdmin: makeAddr("contractAdmin"),
            contractURI: "contractURI",
            contractName: "contractName",
            additionalAdmins: additionalPremintAdmins
        });

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

    function createEthToken(uint256 tokenId, uint256 pricePerToken) internal {
        sparksManager.createToken(tokenId, makeEthTokenConfig(pricePerToken));
    }

    function setupTokenIds(uint256[] memory tokenIds, uint256[] memory tokenPrices) private {
        for (uint i = 0; i < tokenIds.length; i++) {
            vm.prank(admin);
            createEthToken(tokenIds[i], uint96(tokenPrices[i]));
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
            uint256 ethPrice = sparks.tokenPrice(tokenIds[i]);
            vm.deal(minter, ethPrice * quantities[i]);
            sparksManager.mintWithEth{value: ethPrice * quantities[i]}(tokenIds[i], quantities[i], minter);
        }
    }

    function _makeMockSafeTransferRecipient() private returns (ERC1271WalletMock recipient, bytes memory dataToCall) {
        recipient = new ERC1271WalletMock(collector);

        dataToCall = bytes("call the contract");
    }

    event TransferBatchWithData(address from, address to, uint256[] tokenIds, uint256[] quantities, bytes data);
    event TransferSingleWithData(address from, address to, uint256 tokenId, uint256 quantity, bytes data);

    function test_safeTransferFrom_emitsTransferSingleWithData() external {
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 1;

        setupTokenIds(tokenIds);

        uint256[] memory quantities = new uint256[](1);
        quantities[0] = 5;
        mintQuantities(collector, tokenIds, quantities);

        address recipient = makeAddr("recipient");
        bytes memory dataToCall = bytes("call the contract");

        vm.expectEmit(true, true, true, true);
        emit TransferSingleWithData(collector, recipient, tokenIds[0], quantities[0], dataToCall);

        vm.prank(collector);
        sparks.safeTransferFrom(collector, address(recipient), tokenIds[0], quantities[0], dataToCall);

        assertEq(sparks.balanceOfAccount(collector), 0);
        assertEq(sparks.balanceOfAccount(recipient), quantities[0]);
    }

    function test_safeTransferBatchFrom_emitsTransferBatchWithData() external {
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 1;
        tokenIds[1] = 2;

        setupTokenIds(tokenIds);

        uint256[] memory quantities = new uint256[](2);
        quantities[0] = 5;
        quantities[1] = 3;
        mintQuantities(collector, tokenIds, quantities);

        address recipient = makeAddr("recipient");
        bytes memory dataToCall = bytes("call the contract");

        vm.expectEmit(true, true, true, true);
        emit TransferBatchWithData(collector, recipient, tokenIds, quantities, dataToCall);

        vm.prank(collector);
        sparks.safeBatchTransferFrom(collector, address(recipient), tokenIds, quantities, dataToCall);

        assertEq(sparks.balanceOfAccount(collector), 0);
        assertEq(sparks.balanceOfAccount(recipient), quantities[0] + quantities[1]);
    }

    function test_permitSafeTransferBatch_whenEOA_transfersAndSendsDataToContract() external {
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 2;
        tokenIds[1] = 3;

        setupTokenIds(tokenIds);

        uint256[] memory quantities = new uint256[](2);
        quantities[0] = 5;
        quantities[1] = 3;
        mintQuantities(collector, tokenIds, quantities);

        (ERC1271WalletMock recipient, bytes memory dataToCall) = _makeMockSafeTransferRecipient();

        IZoraSparks1155Managed.PermitBatch memory permit = IZoraSparks1155Managed.PermitBatch({
            owner: collector,
            to: address(recipient),
            tokenIds: tokenIds,
            quantities: quantities,
            safeTransferData: dataToCall,
            deadline: block.timestamp + 100,
            nonce: globalNonce++
        });

        bytes memory signature = _signPermit(permit, collectorPrivateKey);

        vm.expectEmit(true, true, true, true);
        emit TransferBatchWithData(collector, address(recipient), tokenIds, quantities, dataToCall);

        // call arguments are: (address operator, address from, uint256 id, uint256 value, bytes data)
        vm.expectCall(address(recipient), 0, abi.encodeCall(recipient.onERC1155BatchReceived, (operator, collector, tokenIds, quantities, dataToCall)));

        vm.prank(operator);
        sparks.permitSafeTransferBatch(permit, signature);

        assertEq(sparks.balanceOfAccount(collector), 0);
    }

    function test_permitSafeTransferSingle_whenEOA_transfersAndSendsDataToContract() external {
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 2;

        setupTokenIds(tokenIds);

        uint256[] memory quantities = new uint256[](1);
        quantities[0] = 5;
        mintQuantities(collector, tokenIds, quantities);

        (ERC1271WalletMock recipient, bytes memory dataToCall) = _makeMockSafeTransferRecipient();

        IZoraSparks1155Managed.PermitSingle memory permit = IZoraSparks1155Managed.PermitSingle({
            owner: collector,
            to: address(recipient),
            tokenId: tokenIds[0],
            quantity: quantities[0],
            safeTransferData: dataToCall,
            deadline: block.timestamp + 100,
            nonce: globalNonce++
        });

        bytes memory signature = _signPermitSingle(permit, collectorPrivateKey);

        vm.expectEmit(true, true, true, true);
        emit TransferSingleWithData(collector, address(recipient), tokenIds[0], quantities[0], dataToCall);

        vm.expectCall(address(recipient), 0, abi.encodeCall(recipient.onERC1155Received, (operator, collector, tokenIds[0], quantities[0], dataToCall)));

        vm.prank(operator);
        sparks.permitSafeTransfer(permit, signature);

        assertEq(sparks.balanceOfAccount(collector), 0);
    }

    function test_permitSafeTransferBatch_whenEOA_revertsWhen_invalidSignature() external {
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 2;

        setupTokenIds(tokenIds);

        uint256[] memory quantities = new uint256[](1);
        quantities[0] = 5;
        mintQuantities(collector, tokenIds, quantities);

        (ERC1271WalletMock recipient, bytes memory dataToCall) = _makeMockSafeTransferRecipient();

        IZoraSparks1155Managed.PermitBatch memory permit = IZoraSparks1155Managed.PermitBatch({
            owner: collector,
            to: address(recipient),
            tokenIds: tokenIds,
            quantities: quantities,
            safeTransferData: dataToCall,
            deadline: block.timestamp + 100,
            nonce: globalNonce++
        });

        (, uint256 anotherPrivateKey) = makeAddrAndKey("anotherPrivateKey");

        bytes memory signature = _signPermit(permit, anotherPrivateKey);

        vm.expectRevert(IZoraSparks1155Managed.InvalidSignature.selector);
        sparks.permitSafeTransferBatch(permit, signature);
    }

    function test_permitSafeTransferSingle_whenEOA_revertsWhen_invalidSignature() external {
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 2;

        setupTokenIds(tokenIds);

        uint256[] memory quantities = new uint256[](1);
        quantities[0] = 5;
        mintQuantities(collector, tokenIds, quantities);

        (ERC1271WalletMock recipient, bytes memory dataToCall) = _makeMockSafeTransferRecipient();

        IZoraSparks1155Managed.PermitSingle memory permit = IZoraSparks1155Managed.PermitSingle({
            owner: collector,
            to: address(recipient),
            tokenId: tokenIds[0],
            quantity: quantities[0],
            safeTransferData: dataToCall,
            deadline: block.timestamp + 100,
            nonce: globalNonce++
        });

        (, uint256 anotherPrivateKey) = makeAddrAndKey("anotherPrivateKey");

        bytes memory signature = _signPermitSingle(permit, anotherPrivateKey);

        vm.expectRevert(IZoraSparks1155Managed.InvalidSignature.selector);
        sparks.permitSafeTransfer(permit, signature);
    }

    function test_permitSafeTransferBatch_whenEOA_revertsWhen_signatureAlreadyUsed() external {
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 2;

        setupTokenIds(tokenIds);

        uint256[] memory quantities = new uint256[](1);
        quantities[0] = 5;
        mintQuantities(collector, tokenIds, quantities);

        (ERC1271WalletMock recipient, bytes memory dataToCall) = _makeMockSafeTransferRecipient();

        IZoraSparks1155Managed.PermitBatch memory permit = IZoraSparks1155Managed.PermitBatch({
            owner: collector,
            to: address(recipient),
            tokenIds: tokenIds,
            quantities: quantities,
            safeTransferData: dataToCall,
            deadline: block.timestamp + 100,
            nonce: globalNonce++
        });

        // collect not full amount, so we can call again
        permit.quantities[0] = 3;

        bytes memory signature = _signPermit(permit, collectorPrivateKey);

        sparks.permitSafeTransferBatch(permit, signature);
        vm.expectRevert(abi.encodeWithSelector(UnorderedNonces.InvalidAccountNonce.selector, collector, 0));
        sparks.permitSafeTransferBatch(permit, signature);

        // collect more with a new signature, it should pass
        permit.quantities[0] = 2;

        // sign again with new nonce
        permit.nonce = globalNonce++;
        signature = _signPermit(permit, collectorPrivateKey);
        sparks.permitSafeTransferBatch(permit, signature);
    }

    function test_permitSafeTransferSingle_whenEOA_revertsWhen_signatureAlreadyUsed() external {
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 2;

        setupTokenIds(tokenIds);

        uint256[] memory quantities = new uint256[](1);
        quantities[0] = 5;
        mintQuantities(collector, tokenIds, quantities);

        (ERC1271WalletMock recipient, bytes memory dataToCall) = _makeMockSafeTransferRecipient();

        IZoraSparks1155Managed.PermitSingle memory permit = IZoraSparks1155Managed.PermitSingle({
            owner: collector,
            to: address(recipient),
            tokenId: tokenIds[0],
            quantity: quantities[0],
            safeTransferData: dataToCall,
            deadline: block.timestamp + 100,
            nonce: globalNonce++
        });

        // collect not full amount, so we can call again
        permit.quantity = 3;

        bytes memory signature = _signPermitSingle(permit, collectorPrivateKey);

        sparks.permitSafeTransfer(permit, signature);
        vm.expectRevert(abi.encodeWithSelector(UnorderedNonces.InvalidAccountNonce.selector, collector, 0));
        sparks.permitSafeTransfer(permit, signature);

        // collect more with a new signature, it should pass
        permit.quantity = 2;
        permit.nonce = globalNonce++;

        // sign again with new nonce
        signature = _signPermitSingle(permit, collectorPrivateKey);
        sparks.permitSafeTransfer(permit, signature);
    }

    function test_permitSafeTransferBatch_whenEOA_revertsWhen_deadlineExpired() external {
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 2;

        setupTokenIds(tokenIds);

        uint256[] memory quantities = new uint256[](1);
        quantities[0] = 5;
        mintQuantities(collector, tokenIds, quantities);

        (ERC1271WalletMock recipient, ) = _makeMockSafeTransferRecipient();

        IZoraSparks1155Managed.PermitBatch memory permit = IZoraSparks1155Managed.PermitBatch({
            owner: collector,
            to: address(recipient),
            tokenIds: tokenIds,
            quantities: quantities,
            safeTransferData: "",
            deadline: block.timestamp - 1,
            nonce: globalNonce++
        });

        bytes memory signature = _signPermit(permit, collectorPrivateKey);

        vm.expectRevert(abi.encodeWithSelector(IZoraSparks1155Managed.ERC2612ExpiredSignature.selector, block.timestamp));
        sparks.permitSafeTransferBatch(permit, signature);
    }

    function test_permitSafeTransferSingle_whenEOA_revertsWhen_deadlineExpired() external {
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 2;

        setupTokenIds(tokenIds);

        uint256[] memory quantities = new uint256[](1);
        quantities[0] = 5;
        mintQuantities(collector, tokenIds, quantities);

        (ERC1271WalletMock recipient, ) = _makeMockSafeTransferRecipient();

        IZoraSparks1155Managed.PermitSingle memory permit = IZoraSparks1155Managed.PermitSingle({
            owner: collector,
            to: address(recipient),
            tokenId: tokenIds[0],
            quantity: quantities[0],
            safeTransferData: "",
            deadline: block.timestamp - 1,
            nonce: globalNonce++
        });

        bytes memory signature = _signPermitSingle(permit, collectorPrivateKey);

        vm.expectRevert(abi.encodeWithSelector(IZoraSparks1155Managed.ERC2612ExpiredSignature.selector, block.timestamp));
        sparks.permitSafeTransfer(permit, signature);
    }

    function test_permitSafeTransferBatch_whenContract_canCollect() external {
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 1;
        tokenIds[1] = 2;

        setupTokenIds(tokenIds);

        ERC1271WalletMock walletMock = new ERC1271WalletMock(collector);

        uint256[] memory quantities = new uint256[](2);
        quantities[0] = 5;
        quantities[1] = 6;
        mintQuantities(address(walletMock), tokenIds, quantities);

        (ERC1271WalletMock recipient, bytes memory dataToCall) = _makeMockSafeTransferRecipient();

        IZoraSparks1155Managed.PermitBatch memory permit = IZoraSparks1155Managed.PermitBatch({
            // smart contract wallet is the once that is to be the permit signer
            owner: address(walletMock),
            to: address(recipient),
            tokenIds: tokenIds,
            quantities: quantities,
            safeTransferData: dataToCall,
            deadline: block.timestamp + 100,
            nonce: globalNonce++
        });

        // smart contract wallet is the once that is to be the permit signer
        bytes memory signature = _signPermit(permit, collectorPrivateKey);

        vm.expectCall(
            address(recipient),
            0,
            abi.encodeCall(recipient.onERC1155BatchReceived, (operator, address(walletMock), tokenIds, quantities, dataToCall))
        );

        vm.prank(operator);
        sparks.permitSafeTransferBatch(permit, signature);

        assertEq(sparks.balanceOfAccount(address(walletMock)), 0);
    }

    function test_permitSafeTransferSingle_whenContract_canCollect() external {
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 2;

        setupTokenIds(tokenIds);

        ERC1271WalletMock walletMock = new ERC1271WalletMock(collector);

        uint256[] memory quantities = new uint256[](1);
        quantities[0] = 5;
        mintQuantities(address(walletMock), tokenIds, quantities);

        (ERC1271WalletMock recipient, bytes memory dataToCall) = _makeMockSafeTransferRecipient();

        IZoraSparks1155Managed.PermitSingle memory permit = IZoraSparks1155Managed.PermitSingle({
            // smart contract wallet is the once that is to be the permit signer
            owner: address(walletMock),
            to: address(recipient),
            tokenId: tokenIds[0],
            quantity: quantities[0],
            safeTransferData: dataToCall,
            deadline: block.timestamp + 100,
            nonce: globalNonce++
        });

        // smart contract wallet is the once that is to be the permit signer
        bytes memory signature = _signPermitSingle(permit, collectorPrivateKey);

        vm.expectCall(
            address(recipient),
            0,
            abi.encodeCall(recipient.onERC1155Received, (operator, address(walletMock), tokenIds[0], quantities[0], dataToCall))
        );

        vm.prank(operator);
        sparks.permitSafeTransfer(permit, signature);

        assertEq(sparks.balanceOfAccount(address(walletMock)), 0);
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

        IZoraSparks1155Managed.PermitBatch memory permit = IZoraSparks1155Managed.PermitBatch({
            // smart contract wallet is the once that is to be the permit signer
            owner: address(walletMock),
            to: address(sparksManager),
            tokenIds: tokenIds,
            quantities: quantities,
            safeTransferData: "",
            deadline: block.timestamp + 100,
            nonce: globalNonce++
        });

        // smart contract wallet is the once that is to be the permit signer
        bytes memory signature = _signPermit(permit, collectorPrivateKey);

        vm.expectRevert(IZoraSparks1155Managed.InvalidSignature.selector);
        sparks.permitSafeTransferBatch(permit, signature);
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

        IZoraSparks1155Managed.PermitSingle memory permit = IZoraSparks1155Managed.PermitSingle({
            // smart contract wallet is the once that is to be the permit signer
            owner: address(walletMock),
            to: address(sparksManager),
            tokenId: tokenIds[0],
            quantity: quantities[0],
            safeTransferData: "",
            deadline: block.timestamp + 100,
            nonce: globalNonce++
        });

        // smart contract wallet is the once that is to be the permit signer
        bytes memory signature = _signPermitSingle(permit, collectorPrivateKey);

        vm.expectRevert(IZoraSparks1155Managed.InvalidSignature.selector);
        sparks.permitSafeTransfer(permit, signature);
    }

    function _signPermit(IZoraSparks1155Managed.PermitBatch memory permit, uint256 privateKey) private view returns (bytes memory signature) {
        bytes32 digest = sparks.hashPermitBatch(permit);

        // create a signature with the digest for the params
        signature = _sign(privateKey, digest);
    }

    function _signPermitSingle(IZoraSparks1155Managed.PermitSingle memory permit, uint256 privateKey) private view returns (bytes memory signature) {
        bytes32 digest = sparks.hashPermitSingle(permit);

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
