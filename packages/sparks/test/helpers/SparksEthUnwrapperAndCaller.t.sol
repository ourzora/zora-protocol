// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";

import {ZoraSparks1155} from "../../src/ZoraSparks1155.sol";
import {ContractCreationConfig, PremintConfigV2, TokenCreationConfigV2, MintArguments, PremintResult} from "@zoralabs/shared-contracts/entities/Premint.sol";
import {ZoraSparksManagerImpl} from "../../src/ZoraSparksManagerImpl.sol";
import {ZoraSparksFixtures} from "../fixtures/ZoraSparksFixtures.sol";
import {SparksEthUnwrapperAndCaller, IUnwrapAndForwardAction} from "../../src/helpers/SparksEthUnwrapperAndCaller.sol";
import {TokenConfig} from "../../src/ZoraSparksTypes.sol";
import {IZoraSparks1155Managed} from "../../src/interfaces/IZoraSparks1155Managed.sol";

contract MockReceiverContract {
    function mockReceiveFunction(string memory argument) external payable {
        if (bytes(argument).length == 0) {
            revert("Argument must not be empty");
        }
    }
}

contract ZoraSparks1155Test is Test {
    address admin = makeAddr("admin");
    address proxyAdmin = makeAddr("proxyAdmin");
    address collector;
    uint256 collectorPrivateKey;

    ZoraSparks1155 sparks;

    uint256 initialTokenId = 995;
    uint256 initialTokenPrice = 0.086 ether;

    ContractCreationConfig contractCreationConfig;

    TokenCreationConfigV2 tokenCreationConfig;

    PremintConfigV2 premintConfig;

    MintArguments mintArguments;

    address signerContract = makeAddr("signerContract");

    ZoraSparksManagerImpl sparksManager;

    // build main contract which were testing
    SparksEthUnwrapperAndCaller sparksEthUnwrapperAndCaller;

    function setUp() external {
        (collector, collectorPrivateKey) = makeAddrAndKey("collector");
        (sparks, sparksManager) = ZoraSparksFixtures.setupSparksProxyWithMockPreminter(proxyAdmin, admin, initialTokenId, initialTokenPrice);

        sparksEthUnwrapperAndCaller = new SparksEthUnwrapperAndCaller(sparks);
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

    function test_sparksValueCanBeUnwrapped_whenBatchMint_toCallMintFunction() external {
        // 1. Mint some eth based tokens
        uint256[] memory quantities = new uint256[](2);
        quantities[0] = 3;
        quantities[1] = 2;

        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = initialTokenId;
        tokenIds[1] = 3;

        vm.deal(collector, 100 ether);

        vm.startPrank(collector);
        sparksManager.mintWithEth{value: initialTokenPrice * quantities[0]}(tokenIds[0], quantities[0], collector);
        vm.stopPrank();

        vm.prank(admin);
        sparksManager.createToken(tokenIds[1], TokenConfig({price: 0.5 ether, tokenAddress: address(0), redeemHandler: address(0)}));

        vm.startPrank(collector);
        sparksManager.mintWithEth{value: 0.5 ether * quantities[1]}(tokenIds[1], quantities[1], collector);
        vm.stopPrank();

        uint256 valueMinted = 100 ether - collector.balance;

        // 2. Setup unwrap call
        // setup mock receiver contract that will receive eith with some call
        MockReceiverContract mockReceiverContract = new MockReceiverContract();

        bytes memory mockReceiverCall = abi.encodeWithSelector(mockReceiverContract.mockReceiveFunction.selector, "randomArgument");

        // this is how much value will be forwarded to the receiver
        uint256 valueToSend = 0.2 ether;
        uint256 expectedValueRefunded = valueMinted - valueToSend;
        uint256 collectorBalanceBefore = collector.balance;

        // encode call to call on the receiver
        bytes memory encodedCall = abi.encodeWithSelector(
            IUnwrapAndForwardAction.callWithEth.selector,
            address(mockReceiverContract),
            mockReceiverCall,
            valueToSend
        );

        // receiver should be called with the value to send, and the encoded call above
        vm.expectCall(address(mockReceiverContract), valueToSend, abi.encodeCall(mockReceiverContract.mockReceiveFunction, "randomArgument"));

        vm.prank(collector);
        sparks.safeBatchTransferFrom(collector, address(sparksEthUnwrapperAndCaller), tokenIds, quantities, encodedCall);

        // make sure the value was refunded
        assertEq(collector.balance, collectorBalanceBefore + expectedValueRefunded);
        assertEq(address(mockReceiverContract).balance, valueToSend);
    }

    function test_sparksValueCanBeUnwrapped_whenSingleMint_toCallMintFunction() external {
        // 1. Mint some eth based tokens
        uint256 quantity = 3;

        uint256 tokenId = initialTokenId;

        vm.deal(collector, 100 ether);

        vm.startPrank(collector);
        sparksManager.mintWithEth{value: initialTokenPrice * quantity}(tokenId, quantity, collector);
        vm.stopPrank();

        uint256 valueMinted = 100 ether - collector.balance;

        // 2. Setup unwrap call
        // setup mock receiver contract that will receive eith with some call
        MockReceiverContract mockReceiverContract = new MockReceiverContract();

        bytes memory mockReceiverCall = abi.encodeWithSelector(mockReceiverContract.mockReceiveFunction.selector, "randomArgument");

        // this is how much value will be forwarded to the receiver
        uint256 valueToSend = 0.2 ether;
        uint256 expectedValueRefunded = valueMinted - valueToSend;
        uint256 collectorBalanceBefore = collector.balance;

        // encode call to call on the receiver
        bytes memory encodedCall = abi.encodeWithSelector(
            IUnwrapAndForwardAction.callWithEth.selector,
            address(mockReceiverContract),
            mockReceiverCall,
            valueToSend
        );

        // receiver should be called with the value to send, and the encoded call above
        vm.expectCall(address(mockReceiverContract), valueToSend, abi.encodeCall(mockReceiverContract.mockReceiveFunction, "randomArgument"));

        vm.prank(collector);
        sparks.safeTransferFrom(collector, address(sparksEthUnwrapperAndCaller), tokenId, quantity, encodedCall);

        // make sure the value was refunded
        assertEq(collector.balance, collectorBalanceBefore + expectedValueRefunded);
        assertEq(address(mockReceiverContract).balance, valueToSend);
    }

    function test_sparksValueCanBeUnwrapped_whenSingleMint_revertsWhen_callFails() external {
        uint256 quantity = 3;

        uint256 tokenId = initialTokenId;

        vm.deal(collector, 100 ether);

        vm.startPrank(collector);
        sparksManager.mintWithEth{value: initialTokenPrice * quantity}(tokenId, quantity, collector);
        vm.stopPrank();

        // 2. Setup unwrap call
        // setup mock receiver contract that will receive eith with some call
        MockReceiverContract mockReceiverContract = new MockReceiverContract();

        // here we build an empty string for the argument which would result in it failing.
        bytes memory mockReceiverCall = abi.encodeWithSelector(mockReceiverContract.mockReceiveFunction.selector, "");

        // this is how much value will be forwarded to the receiver
        uint256 valueToSend = 0.2 ether;

        // encode call to call on the receiver
        bytes memory encodedCall = abi.encodeWithSelector(
            IUnwrapAndForwardAction.callWithEth.selector,
            address(mockReceiverContract),
            mockReceiverCall,
            valueToSend
        );

        vm.prank(collector);
        vm.expectRevert();
        sparks.safeTransferFrom(collector, address(sparksEthUnwrapperAndCaller), tokenId, quantity, encodedCall);
    }

    function test_permitWithAdditionalValue_sendsAdditionalValueWithCall() external {
        // 1. Mint some eth based tokens
        uint256[] memory quantities = new uint256[](1);
        quantities[0] = 3;

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = initialTokenId;

        vm.deal(collector, 100 ether);

        vm.startPrank(collector);
        sparksManager.mintWithEth{value: initialTokenPrice * quantities[0]}(tokenIds[0], quantities[0], collector);
        vm.stopPrank();

        uint256 valueMinted = 100 ether - collector.balance;

        // 2. Setup unwrap call
        // setup mock receiver contract that will receive eith with some call
        MockReceiverContract mockReceiverContract = new MockReceiverContract();

        bytes memory mockReceiverCall = abi.encodeWithSelector(mockReceiverContract.mockReceiveFunction.selector, "randomArgument");

        uint256 additionalToSend = 0.2 ether;
        // lets forward more value to the receiver than is in the unwrapped value
        uint256 valueToSend = valueMinted + additionalToSend;

        // encode call to call on the receiver
        bytes memory encodedCall = abi.encodeWithSelector(
            IUnwrapAndForwardAction.callWithEth.selector,
            address(mockReceiverContract),
            mockReceiverCall,
            valueToSend
        );

        IZoraSparks1155Managed.PermitBatch memory permit = IZoraSparks1155Managed.PermitBatch({
            owner: collector,
            to: address(sparksEthUnwrapperAndCaller),
            tokenIds: tokenIds,
            quantities: quantities,
            safeTransferData: encodedCall,
            deadline: block.timestamp + 100,
            nonce: 1
        });

        bytes memory signature = _signPermit(permit, collectorPrivateKey);

        // receiver should be called with the value to send, and the encoded call above
        vm.expectCall(address(mockReceiverContract), valueToSend, abi.encodeCall(mockReceiverContract.mockReceiveFunction, "randomArgument"));

        vm.prank(collector);
        sparksEthUnwrapperAndCaller.permitWithAdditionalValue{value: additionalToSend}(permit, signature);

        // make sure the value was refunded
        assertEq(address(mockReceiverContract).balance, valueToSend);
    }

    function _signPermit(IZoraSparks1155Managed.PermitBatch memory permit, uint256 privateKey) private view returns (bytes memory signature) {
        bytes32 digest = sparks.hashPermitBatch(permit);

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
