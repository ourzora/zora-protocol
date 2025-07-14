// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import {ERC20PresetMinterPauser} from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import {ERC721PresetMinterPauserAutoId} from "@openzeppelin/contracts/token/ERC721/presets/ERC721PresetMinterPauserAutoId.sol";
import {ERC1155PresetMinterPauser} from "@openzeppelin/contracts/token/ERC1155/presets/ERC1155PresetMinterPauser.sol";
import {ProtocolRewards} from "@zoralabs/protocol-rewards/src/ProtocolRewards.sol";
import {ZoraCreator1155Impl} from "../../../src/nft/ZoraCreator1155Impl.sol";
import {Zora1155} from "../../../src/proxies/Zora1155.sol";
import {IZoraCreator1155} from "../../../src/interfaces/IZoraCreator1155.sol";
import {IRenderer1155} from "../../../src/interfaces/IRenderer1155.sol";
import {ICreatorRoyaltiesControl} from "../../../src/interfaces/ICreatorRoyaltiesControl.sol";
import {IZoraCreator1155Factory} from "../../../src/interfaces/IZoraCreator1155Factory.sol";
import {ZoraCreatorRedeemMinterStrategy} from "../../../src/minters/redeem/ZoraCreatorRedeemMinterStrategy.sol";

/// @notice Contract versions after v1.4.0 will not support burn to redeem
contract ZoraCreatorRedeemMinterStrategyTest is Test {
    ProtocolRewards internal protocolRewards;
    ZoraCreator1155Impl internal target;
    ZoraCreatorRedeemMinterStrategy internal redeemMinter;
    address payable internal admin = payable(address(0x999));
    uint256 internal newTokenId;
    address internal zora;
    address[] internal rewardRecipients;

    event RedeemSet(address indexed target, bytes32 indexed redeemsInstructionsHash, ZoraCreatorRedeemMinterStrategy.RedeemInstructions data);
    event RedeemProcessed(address indexed target, bytes32 indexed redeemsInstructionsHash, address sender, uint256[][] tokenIds, uint256[][] amounts);
    event RedeemsCleared(address indexed target, bytes32[] indexed redeemInstructionsHashes);

    function setUp() external {
        zora = makeAddr("zora");
        rewardRecipients = new address[](1);
        bytes[] memory emptyData = new bytes[](0);
        protocolRewards = new ProtocolRewards();
        ZoraCreator1155Impl targetImpl = new ZoraCreator1155Impl(zora, address(0x2134), address(protocolRewards), makeAddr("timedSaleStrategy"));
        Zora1155 proxy = new Zora1155(address(targetImpl));
        target = ZoraCreator1155Impl(payable(address(proxy)));
        target.initialize("test", "test", ICreatorRoyaltiesControl.RoyaltyConfiguration(0, 0, address(0)), admin, emptyData);
        redeemMinter = new ZoraCreatorRedeemMinterStrategy();
        redeemMinter.initialize(address(target));
        vm.startPrank(admin);
        newTokenId = target.setupNewToken("https://zora.co/testing/token.json", 10);
        target.addPermission(newTokenId, address(redeemMinter), target.PERMISSION_BIT_MINTER());
        vm.stopPrank();
    }

    function test_ContractURI() external {
        assertEq(redeemMinter.contractURI(), "https://github.com/ourzora/zora-1155-contracts/");
    }

    function test_ContractName() external {
        assertEq(redeemMinter.contractName(), "Redeem Minter Sale Strategy");
    }

    function test_Version() external {
        assertEq(redeemMinter.contractVersion(), "1.1.0");
    }

    function test_OnlyDropContractCanCallWriteFunctions() external {
        ZoraCreatorRedeemMinterStrategy.RedeemInstructions memory redeemInstructions;
        vm.startPrank(address(admin));

        vm.expectRevert(abi.encodeWithSignature("CallerNotCreatorContract()"));
        redeemMinter.setRedeem(0, redeemInstructions);

        bytes32[] memory hashes = new bytes32[](0);
        vm.expectRevert(abi.encodeWithSignature("CallerNotCreatorContract()"));
        redeemMinter.clearRedeem(0, hashes);

        vm.expectRevert(abi.encodeWithSignature("CallerNotCreatorContract()"));
        redeemMinter.requestMint(address(0), 0, 0, 0, bytes(""));

        vm.expectRevert(abi.encodeWithSignature("CallerNotCreatorContract()"));
        redeemMinter.resetSale(0);

        vm.stopPrank();
    }

    ///////// SET REDEEM /////////

    function test_SetRedeem() external {
        vm.startPrank(admin);

        address tokenRecipient = address(322);
        vm.deal(tokenRecipient, 20 ether);

        ERC20PresetMinterPauser burnToken = new ERC20PresetMinterPauser("Random Token", "RAND");
        burnToken.mint(address(tokenRecipient), 1000);

        ZoraCreatorRedeemMinterStrategy.MintToken memory mintToken = ZoraCreatorRedeemMinterStrategy.MintToken({
            tokenContract: address(target),
            tokenId: newTokenId,
            amount: 10,
            tokenType: ZoraCreatorRedeemMinterStrategy.TokenType.ERC1155
        });
        ZoraCreatorRedeemMinterStrategy.RedeemInstruction[] memory instructions = new ZoraCreatorRedeemMinterStrategy.RedeemInstruction[](1);
        instructions[0] = ZoraCreatorRedeemMinterStrategy.RedeemInstruction({
            tokenType: ZoraCreatorRedeemMinterStrategy.TokenType.ERC20,
            amount: 500,
            tokenIdStart: 0,
            tokenIdEnd: 0,
            tokenContract: address(burnToken),
            transferRecipient: address(0),
            burnFunction: bytes4(keccak256(bytes("burnFrom(address,uint256)")))
        });
        ZoraCreatorRedeemMinterStrategy.RedeemInstructions memory redeemInstructions = ZoraCreatorRedeemMinterStrategy.RedeemInstructions({
            mintToken: mintToken,
            instructions: instructions,
            saleStart: 0,
            saleEnd: type(uint64).max,
            ethAmount: 1 ether,
            ethRecipient: address(0)
        });
        vm.stopPrank();

        vm.expectEmit(true, true, false, true);
        emit RedeemSet(address(target), keccak256(abi.encode(redeemInstructions)), redeemInstructions);
        vm.startPrank(address(target));
        redeemMinter.setRedeem(newTokenId, redeemInstructions);
        vm.expectRevert(abi.encodeWithSignature("RedeemInstructionAlreadySet()"));
        redeemMinter.setRedeem(newTokenId, redeemInstructions);
        vm.stopPrank();

        assertTrue(redeemMinter.redeemInstructionsHashIsAllowed(newTokenId, keccak256(abi.encode(redeemInstructions))));
    }

    function test_SetRedeemInstructionValidation() external {
        address tokenRecipient = address(322);
        vm.deal(tokenRecipient, 20 ether);

        ERC20PresetMinterPauser burnToken = new ERC20PresetMinterPauser("Random Token", "RAND");
        burnToken.mint(address(tokenRecipient), 1000);

        ZoraCreatorRedeemMinterStrategy.MintToken memory mintToken = ZoraCreatorRedeemMinterStrategy.MintToken({
            tokenContract: address(target),
            tokenId: newTokenId,
            amount: 10,
            tokenType: ZoraCreatorRedeemMinterStrategy.TokenType.ERC1155
        });
        ZoraCreatorRedeemMinterStrategy.RedeemInstruction[] memory instructions = new ZoraCreatorRedeemMinterStrategy.RedeemInstruction[](1);
        instructions[0] = ZoraCreatorRedeemMinterStrategy.RedeemInstruction({
            tokenType: ZoraCreatorRedeemMinterStrategy.TokenType.NULL,
            amount: 500,
            tokenIdStart: 0,
            tokenIdEnd: 0,
            tokenContract: address(burnToken),
            transferRecipient: address(0),
            burnFunction: bytes4(keccak256(bytes("burnFrom(address,uint256)")))
        });
        ZoraCreatorRedeemMinterStrategy.RedeemInstructions memory redeemInstructions = ZoraCreatorRedeemMinterStrategy.RedeemInstructions({
            mintToken: mintToken,
            instructions: instructions,
            saleStart: 0,
            saleEnd: type(uint64).max,
            ethAmount: 1 ether,
            ethRecipient: address(0)
        });

        vm.startPrank(address(target));

        // InvalidTokenIdsForTokenType: ERC20 w/ nonzero tokenId start or end
        redeemInstructions.instructions[0].tokenType = ZoraCreatorRedeemMinterStrategy.TokenType.ERC20;
        redeemInstructions.instructions[0].tokenIdStart = 1;
        redeemInstructions.instructions[0].tokenIdEnd = 0;
        vm.expectRevert(abi.encodeWithSignature("InvalidTokenIdsForTokenType()"));
        redeemMinter.setRedeem(newTokenId, redeemInstructions);
        redeemInstructions.instructions[0].tokenIdStart = 0;
        redeemInstructions.instructions[0].tokenIdEnd = 1;
        vm.expectRevert(abi.encodeWithSignature("InvalidTokenIdsForTokenType()"));
        redeemMinter.setRedeem(newTokenId, redeemInstructions);

        // InvalidTokenIdsForTokenType: non ERC20 w/ tokenID start > end
        redeemInstructions.instructions[0].tokenType = ZoraCreatorRedeemMinterStrategy.TokenType.ERC721;
        redeemInstructions.instructions[0].tokenIdStart = 4;
        redeemInstructions.instructions[0].tokenIdEnd = 2;
        vm.expectRevert(abi.encodeWithSignature("InvalidTokenIdsForTokenType()"));
        redeemMinter.setRedeem(newTokenId, redeemInstructions);
        redeemInstructions.mintToken.tokenType = ZoraCreatorRedeemMinterStrategy.TokenType.ERC1155;
        vm.expectRevert(abi.encodeWithSignature("InvalidTokenIdsForTokenType()"));
        redeemMinter.setRedeem(newTokenId, redeemInstructions);
        redeemInstructions.instructions[0].tokenIdStart = 0;
        redeemInstructions.instructions[0].tokenIdEnd = 0;

        // InvalidTokenType: tokenType is NULL
        redeemInstructions.instructions[0].tokenType = ZoraCreatorRedeemMinterStrategy.TokenType.NULL;
        vm.expectRevert(abi.encodeWithSignature("InvalidTokenType()"));
        redeemMinter.setRedeem(newTokenId, redeemInstructions);
        redeemInstructions.instructions[0].tokenType = ZoraCreatorRedeemMinterStrategy.TokenType.ERC1155;

        // MustBurnOrTransfer: both transferRecipient and burnFunction are 0
        redeemInstructions.instructions[0].transferRecipient = address(0);
        redeemInstructions.instructions[0].burnFunction = bytes4(0);
        vm.expectRevert(abi.encodeWithSignature("MustBurnOrTransfer()"));
        redeemMinter.setRedeem(newTokenId, redeemInstructions);

        // MustBurnOrTransfer: both transferRecipient and burnFunction are non-zero
        redeemInstructions.instructions[0].transferRecipient = address(1);
        redeemInstructions.instructions[0].burnFunction = bytes4(keccak256(bytes("burnFrom(address,uint256)")));
        vm.expectRevert(abi.encodeWithSignature("MustBurnOrTransfer()"));
        redeemMinter.setRedeem(newTokenId, redeemInstructions);
        redeemInstructions.instructions[0].transferRecipient = address(0);

        // IncorrectMintAmount
        redeemInstructions.instructions[0].amount = 0;
        vm.expectRevert(abi.encodeWithSignature("IncorrectMintAmount()"));
        redeemMinter.setRedeem(newTokenId, redeemInstructions);
        redeemInstructions.instructions[0].amount = 500;

        // InvalidSaleEndOrStart: start > end
        redeemInstructions.saleStart = 1;
        redeemInstructions.saleEnd = 0;
        vm.expectRevert(abi.encodeWithSignature("InvalidSaleEndOrStart()"));
        redeemMinter.setRedeem(newTokenId, redeemInstructions);
        redeemInstructions.saleStart = 0;
        redeemInstructions.saleEnd = type(uint64).max;

        // InvalidSaleEndOrStart: block.timestamp > end
        redeemInstructions.saleStart = 0;
        redeemInstructions.saleEnd = 1 days;
        vm.warp(2 days);
        vm.expectRevert(abi.encodeWithSignature("InvalidSaleEndOrStart()"));
        redeemMinter.setRedeem(newTokenId, redeemInstructions);
        redeemInstructions.saleEnd = type(uint64).max;

        // EmptyRedeemInstructions();
        redeemInstructions.instructions = new ZoraCreatorRedeemMinterStrategy.RedeemInstruction[](0);
        vm.expectRevert(abi.encodeWithSignature("EmptyRedeemInstructions()"));
        redeemMinter.setRedeem(newTokenId, redeemInstructions);
        redeemInstructions.instructions = instructions;

        // MintTokenContractMustBeCreatorContract
        redeemInstructions.mintToken.tokenContract = address(0);
        vm.expectRevert(abi.encodeWithSignature("MintTokenContractMustBeCreatorContract()"));
        redeemMinter.setRedeem(newTokenId, redeemInstructions);
        redeemInstructions.mintToken.tokenContract = address(target);

        // MintTokenTypeMustBeERC1155:
        redeemInstructions.mintToken.tokenType = ZoraCreatorRedeemMinterStrategy.TokenType.ERC721;
        vm.expectRevert(abi.encodeWithSignature("MintTokenTypeMustBeERC1155()"));
        redeemMinter.setRedeem(newTokenId, redeemInstructions);
    }

    ///////// REQUEST MINT /////////

    function test_MintFlowERC20() external {
        vm.startPrank(admin);

        address tokenRecipient = address(322);
        vm.deal(tokenRecipient, 20 ether);

        ERC20PresetMinterPauser burnToken = new ERC20PresetMinterPauser("Random Token", "RAND");
        burnToken.mint(address(tokenRecipient), 1000);

        ZoraCreatorRedeemMinterStrategy.MintToken memory mintToken = ZoraCreatorRedeemMinterStrategy.MintToken({
            tokenContract: address(target),
            tokenId: newTokenId,
            amount: 10,
            tokenType: ZoraCreatorRedeemMinterStrategy.TokenType.ERC1155
        });
        ZoraCreatorRedeemMinterStrategy.RedeemInstruction[] memory instructions = new ZoraCreatorRedeemMinterStrategy.RedeemInstruction[](1);
        instructions[0] = ZoraCreatorRedeemMinterStrategy.RedeemInstruction({
            tokenType: ZoraCreatorRedeemMinterStrategy.TokenType.ERC20,
            amount: 500,
            tokenIdStart: 0,
            tokenIdEnd: 0,
            tokenContract: address(burnToken),
            transferRecipient: address(0),
            burnFunction: bytes4(keccak256(bytes("burnFrom(address,uint256)")))
        });
        ZoraCreatorRedeemMinterStrategy.RedeemInstructions memory redeemInstructions = ZoraCreatorRedeemMinterStrategy.RedeemInstructions({
            mintToken: mintToken,
            instructions: instructions,
            saleStart: 0,
            saleEnd: type(uint64).max,
            ethAmount: 1 ether,
            ethRecipient: address(0)
        });

        target.callSale(newTokenId, redeemMinter, abi.encodeWithSelector(ZoraCreatorRedeemMinterStrategy.setRedeem.selector, newTokenId, redeemInstructions));
        vm.stopPrank();

        vm.startPrank(tokenRecipient);
        burnToken.approve(address(redeemMinter), 500);
        uint256[][] memory tokenIds = new uint256[][](1);
        tokenIds[0] = new uint256[](0);
        uint256[][] memory amounts = new uint256[][](1);
        amounts[0] = new uint256[](1);
        amounts[0][0] = 500;

        uint256 totalReward = target.computeTotalReward(target.mintFee(), 10);
        vm.deal(tokenRecipient, 1 ether + totalReward);

        vm.expectEmit(true, true, false, false);
        emit RedeemProcessed(address(target), keccak256(abi.encode(redeemInstructions)), tokenRecipient, tokenIds, amounts);
        target.mint{value: 1 ether + totalReward}(redeemMinter, newTokenId, 10, rewardRecipients, abi.encode(redeemInstructions, tokenIds, amounts));
        assertEq(address(target).balance, 1 ether);
        assertEq(target.balanceOf(tokenRecipient, newTokenId), 10);
        assertEq(burnToken.balanceOf(tokenRecipient), 500);
        vm.stopPrank();
    }

    function test_MintFlowERC1155() external {
        vm.startPrank(admin);

        address tokenRecipient = address(322);
        vm.deal(tokenRecipient, 20 ether);

        ERC1155PresetMinterPauser burnToken = new ERC1155PresetMinterPauser("https://zora.co/testing/token.json");
        burnToken.mint(address(tokenRecipient), 1, 1000, "");

        ZoraCreatorRedeemMinterStrategy.MintToken memory mintToken = ZoraCreatorRedeemMinterStrategy.MintToken({
            tokenContract: address(target),
            tokenId: newTokenId,
            amount: 10,
            tokenType: ZoraCreatorRedeemMinterStrategy.TokenType.ERC1155
        });
        ZoraCreatorRedeemMinterStrategy.RedeemInstruction[] memory instructions = new ZoraCreatorRedeemMinterStrategy.RedeemInstruction[](1);
        instructions[0] = ZoraCreatorRedeemMinterStrategy.RedeemInstruction({
            tokenType: ZoraCreatorRedeemMinterStrategy.TokenType.ERC1155,
            amount: 500,
            tokenIdStart: 1,
            tokenIdEnd: 1,
            tokenContract: address(burnToken),
            transferRecipient: address(0),
            burnFunction: bytes4(keccak256(bytes("burnBatch(address,uint256[],uint256[])")))
        });
        ZoraCreatorRedeemMinterStrategy.RedeemInstructions memory redeemInstructions = ZoraCreatorRedeemMinterStrategy.RedeemInstructions({
            mintToken: mintToken,
            instructions: instructions,
            saleStart: 0,
            saleEnd: type(uint64).max,
            ethAmount: 1 ether,
            ethRecipient: address(0)
        });

        target.callSale(newTokenId, redeemMinter, abi.encodeWithSelector(ZoraCreatorRedeemMinterStrategy.setRedeem.selector, newTokenId, redeemInstructions));
        vm.stopPrank();

        vm.startPrank(tokenRecipient);
        burnToken.setApprovalForAll(address(redeemMinter), true);
        uint256[][] memory tokenIds = new uint256[][](1);
        tokenIds[0] = new uint256[](1);
        tokenIds[0][0] = 1;
        uint256[][] memory amounts = new uint256[][](1);
        amounts[0] = new uint256[](1);
        amounts[0][0] = 500;

        uint256 totalReward = target.computeTotalReward(target.mintFee(), 10);
        vm.deal(tokenRecipient, 1 ether + totalReward);
        target.mint{value: 1 ether + totalReward}(redeemMinter, newTokenId, 10, rewardRecipients, abi.encode(redeemInstructions, tokenIds, amounts));

        assertEq(address(target).balance, 1 ether);
        assertEq(target.balanceOf(tokenRecipient, newTokenId), 10);
        assertEq(burnToken.balanceOf(tokenRecipient, 1), 500);
        vm.stopPrank();
    }

    function test_MintFlowERC721() external {
        vm.startPrank(admin);

        address tokenRecipient = address(322);
        vm.deal(tokenRecipient, 20 ether);

        ERC721PresetMinterPauserAutoId burnToken = new ERC721PresetMinterPauserAutoId("Test token", "TEST", "https://zora.co/testing/token.json");
        burnToken.mint(address(tokenRecipient));
        burnToken.mint(address(tokenRecipient));

        ZoraCreatorRedeemMinterStrategy.MintToken memory mintToken = ZoraCreatorRedeemMinterStrategy.MintToken({
            tokenContract: address(target),
            tokenId: newTokenId,
            amount: 10,
            tokenType: ZoraCreatorRedeemMinterStrategy.TokenType.ERC1155
        });
        ZoraCreatorRedeemMinterStrategy.RedeemInstruction[] memory instructions = new ZoraCreatorRedeemMinterStrategy.RedeemInstruction[](1);
        instructions[0] = ZoraCreatorRedeemMinterStrategy.RedeemInstruction({
            tokenType: ZoraCreatorRedeemMinterStrategy.TokenType.ERC721,
            amount: 2,
            tokenIdStart: 0,
            tokenIdEnd: 1,
            tokenContract: address(burnToken),
            transferRecipient: address(0),
            burnFunction: bytes4(keccak256(bytes("burn(uint256)")))
        });
        ZoraCreatorRedeemMinterStrategy.RedeemInstructions memory redeemInstructions = ZoraCreatorRedeemMinterStrategy.RedeemInstructions({
            mintToken: mintToken,
            instructions: instructions,
            saleStart: 0,
            saleEnd: type(uint64).max,
            ethAmount: 1 ether,
            ethRecipient: address(0)
        });

        target.callSale(newTokenId, redeemMinter, abi.encodeWithSelector(ZoraCreatorRedeemMinterStrategy.setRedeem.selector, newTokenId, redeemInstructions));
        vm.stopPrank();

        vm.startPrank(tokenRecipient);
        burnToken.setApprovalForAll(address(redeemMinter), true);
        uint256[][] memory tokenIds = new uint256[][](1);
        tokenIds[0] = new uint256[](2);
        tokenIds[0][0] = 0;
        tokenIds[0][1] = 1;
        uint256[][] memory amounts = new uint256[][](1);

        uint256 totalReward = target.computeTotalReward(target.mintFee(), 10);
        vm.deal(tokenRecipient, 1 ether + totalReward);

        target.mint{value: 1 ether + totalReward}(redeemMinter, newTokenId, 10, rewardRecipients, abi.encode(redeemInstructions, tokenIds, amounts));
        assertEq(address(target).balance, 1 ether);
        assertEq(target.balanceOf(tokenRecipient, newTokenId), 10);
        vm.expectRevert();
        burnToken.ownerOf(0);
        vm.expectRevert();
        burnToken.ownerOf(1);
        vm.stopPrank();
    }

    function test_MintFlowMultiple() external {
        vm.startPrank(admin);

        address tokenRecipient = address(322);
        vm.deal(tokenRecipient, 20 ether);

        ERC20PresetMinterPauser burnTokenERC20 = new ERC20PresetMinterPauser("Random Token", "RAND");
        burnTokenERC20.mint(address(tokenRecipient), 1000);
        ERC1155PresetMinterPauser burnTokenERC1155 = new ERC1155PresetMinterPauser("https://zora.co/testing/token.json");
        burnTokenERC1155.mint(address(tokenRecipient), 1, 1000, "");
        ERC721PresetMinterPauserAutoId burnTokenERC721 = new ERC721PresetMinterPauserAutoId("Test token", "TEST", "https://zora.co/testing/token.json");
        burnTokenERC721.mint(address(tokenRecipient));
        burnTokenERC721.mint(address(tokenRecipient));

        ZoraCreatorRedeemMinterStrategy.MintToken memory mintToken = ZoraCreatorRedeemMinterStrategy.MintToken({
            tokenContract: address(target),
            tokenId: newTokenId,
            amount: 10,
            tokenType: ZoraCreatorRedeemMinterStrategy.TokenType.ERC1155
        });
        ZoraCreatorRedeemMinterStrategy.RedeemInstruction[] memory instructions = new ZoraCreatorRedeemMinterStrategy.RedeemInstruction[](3);
        instructions[0] = ZoraCreatorRedeemMinterStrategy.RedeemInstruction({
            tokenType: ZoraCreatorRedeemMinterStrategy.TokenType.ERC20,
            amount: 500,
            tokenIdStart: 0,
            tokenIdEnd: 0,
            tokenContract: address(burnTokenERC20),
            transferRecipient: address(0),
            burnFunction: bytes4(keccak256(bytes("burnFrom(address,uint256)")))
        });
        instructions[1] = ZoraCreatorRedeemMinterStrategy.RedeemInstruction({
            tokenType: ZoraCreatorRedeemMinterStrategy.TokenType.ERC1155,
            amount: 500,
            tokenIdStart: 1,
            tokenIdEnd: 1,
            tokenContract: address(burnTokenERC1155),
            transferRecipient: address(0),
            burnFunction: bytes4(keccak256(bytes("burnBatch(address,uint256[],uint256[])")))
        });
        instructions[2] = ZoraCreatorRedeemMinterStrategy.RedeemInstruction({
            tokenType: ZoraCreatorRedeemMinterStrategy.TokenType.ERC721,
            amount: 2,
            tokenIdStart: 0,
            tokenIdEnd: 1,
            tokenContract: address(burnTokenERC721),
            transferRecipient: address(0),
            burnFunction: bytes4(keccak256(bytes("burn(uint256)")))
        });
        ZoraCreatorRedeemMinterStrategy.RedeemInstructions memory redeemInstructions = ZoraCreatorRedeemMinterStrategy.RedeemInstructions({
            mintToken: mintToken,
            instructions: instructions,
            saleStart: 0,
            saleEnd: type(uint64).max,
            ethAmount: 1 ether,
            ethRecipient: address(0)
        });

        target.callSale(newTokenId, redeemMinter, abi.encodeWithSelector(ZoraCreatorRedeemMinterStrategy.setRedeem.selector, newTokenId, redeemInstructions));
        vm.stopPrank();

        vm.startPrank(tokenRecipient);
        burnTokenERC20.approve(address(redeemMinter), 500);
        burnTokenERC1155.setApprovalForAll(address(redeemMinter), true);
        burnTokenERC721.setApprovalForAll(address(redeemMinter), true);

        uint256[][] memory tokenIds = new uint256[][](3);
        uint256[][] memory amounts = new uint256[][](3);

        amounts[0] = new uint256[](1);
        amounts[0][0] = 500;

        tokenIds[1] = new uint256[](1);
        tokenIds[1][0] = 1;
        amounts[1] = new uint256[](1);
        amounts[1][0] = 500;

        tokenIds[2] = new uint256[](2);
        tokenIds[2][0] = 0;
        tokenIds[2][1] = 1;

        uint256 totalReward = target.computeTotalReward(target.mintFee(), 10);
        vm.deal(tokenRecipient, 1 ether + totalReward);

        target.mint{value: 1 ether + totalReward}(redeemMinter, newTokenId, 10, rewardRecipients, abi.encode(redeemInstructions, tokenIds, amounts));
        assertEq(address(target).balance, 1 ether);
        assertEq(target.balanceOf(tokenRecipient, newTokenId), 10);
        assertEq(burnTokenERC20.balanceOf(tokenRecipient), 500);
        assertEq(burnTokenERC1155.balanceOf(tokenRecipient, 1), 500);
        assertEq(burnTokenERC721.balanceOf(address(tokenRecipient)), 0);
        vm.stopPrank();
    }

    function test_MintFlowMultipleWithTransferInsteadOfBurn() external {
        vm.startPrank(admin);

        address tokenRecipient = address(322);
        vm.deal(tokenRecipient, 20 ether);
        address redeemTokenRecipient = address(323);

        ERC20PresetMinterPauser burnTokenERC20 = new ERC20PresetMinterPauser("Random Token", "RAND");
        burnTokenERC20.mint(address(tokenRecipient), 1000);
        ERC1155PresetMinterPauser burnTokenERC1155 = new ERC1155PresetMinterPauser("https://zora.co/testing/token.json");
        burnTokenERC1155.mint(address(tokenRecipient), 1, 1000, "");
        ERC721PresetMinterPauserAutoId burnTokenERC721 = new ERC721PresetMinterPauserAutoId("Test token", "TEST", "https://zora.co/testing/token.json");
        burnTokenERC721.mint(address(tokenRecipient));
        burnTokenERC721.mint(address(tokenRecipient));

        ZoraCreatorRedeemMinterStrategy.MintToken memory mintToken = ZoraCreatorRedeemMinterStrategy.MintToken({
            tokenContract: address(target),
            tokenId: newTokenId,
            amount: 10,
            tokenType: ZoraCreatorRedeemMinterStrategy.TokenType.ERC1155
        });
        ZoraCreatorRedeemMinterStrategy.RedeemInstruction[] memory instructions = new ZoraCreatorRedeemMinterStrategy.RedeemInstruction[](3);
        instructions[0] = ZoraCreatorRedeemMinterStrategy.RedeemInstruction({
            tokenType: ZoraCreatorRedeemMinterStrategy.TokenType.ERC20,
            amount: 500,
            tokenIdStart: 0,
            tokenIdEnd: 0,
            tokenContract: address(burnTokenERC20),
            transferRecipient: redeemTokenRecipient,
            burnFunction: 0
        });
        instructions[1] = ZoraCreatorRedeemMinterStrategy.RedeemInstruction({
            tokenType: ZoraCreatorRedeemMinterStrategy.TokenType.ERC1155,
            amount: 500,
            tokenIdStart: 1,
            tokenIdEnd: 1,
            tokenContract: address(burnTokenERC1155),
            transferRecipient: redeemTokenRecipient,
            burnFunction: 0
        });
        instructions[2] = ZoraCreatorRedeemMinterStrategy.RedeemInstruction({
            tokenType: ZoraCreatorRedeemMinterStrategy.TokenType.ERC721,
            amount: 2,
            tokenIdStart: 0,
            tokenIdEnd: 1,
            tokenContract: address(burnTokenERC721),
            transferRecipient: redeemTokenRecipient,
            burnFunction: 0
        });
        ZoraCreatorRedeemMinterStrategy.RedeemInstructions memory redeemInstructions = ZoraCreatorRedeemMinterStrategy.RedeemInstructions({
            mintToken: mintToken,
            instructions: instructions,
            saleStart: 0,
            saleEnd: type(uint64).max,
            ethAmount: 1 ether,
            ethRecipient: address(0)
        });

        target.callSale(newTokenId, redeemMinter, abi.encodeWithSelector(ZoraCreatorRedeemMinterStrategy.setRedeem.selector, newTokenId, redeemInstructions));
        vm.stopPrank();

        vm.startPrank(tokenRecipient);
        burnTokenERC20.approve(address(redeemMinter), 500);
        burnTokenERC1155.setApprovalForAll(address(redeemMinter), true);
        burnTokenERC721.setApprovalForAll(address(redeemMinter), true);

        uint256[][] memory tokenIds = new uint256[][](3);
        uint256[][] memory amounts = new uint256[][](3);

        amounts[0] = new uint256[](1);
        amounts[0][0] = 500;

        tokenIds[1] = new uint256[](1);
        tokenIds[1][0] = 1;
        amounts[1] = new uint256[](1);
        amounts[1][0] = 500;

        tokenIds[2] = new uint256[](2);
        tokenIds[2][0] = 0;
        tokenIds[2][1] = 1;

        uint256 totalReward = target.computeTotalReward(target.mintFee(), 10);
        vm.deal(tokenRecipient, 1 ether + totalReward);

        target.mint{value: 1 ether + totalReward}(redeemMinter, newTokenId, 10, rewardRecipients, abi.encode(redeemInstructions, tokenIds, amounts));
        assertEq(address(target).balance, 1 ether);
        assertEq(target.balanceOf(tokenRecipient, newTokenId), 10);
        assertEq(burnTokenERC20.balanceOf(tokenRecipient), 500);
        assertEq(burnTokenERC20.balanceOf(redeemTokenRecipient), 500);
        assertEq(burnTokenERC1155.balanceOf(tokenRecipient, 1), 500);
        assertEq(burnTokenERC1155.balanceOf(redeemTokenRecipient, 1), 500);
        assertEq(burnTokenERC721.balanceOf(address(tokenRecipient)), 0);
        assertEq(burnTokenERC721.balanceOf(redeemTokenRecipient), 2);

        vm.stopPrank();
    }

    function test_MintFlowTokenIdRangesForERC1155AndERC721() external {
        vm.startPrank(admin);

        address tokenRecipient = address(322);
        vm.deal(tokenRecipient, 20 ether);
        address redeemTokenRecipient = address(323);

        ERC1155PresetMinterPauser burnTokenERC1155 = new ERC1155PresetMinterPauser("https://zora.co/testing/token.json");
        burnTokenERC1155.mint(address(tokenRecipient), 7, 100, "");
        burnTokenERC1155.mint(address(tokenRecipient), 8, 100, "");
        burnTokenERC1155.mint(address(tokenRecipient), 9, 100, "");
        ERC721PresetMinterPauserAutoId burnTokenERC721 = new ERC721PresetMinterPauserAutoId("Test token", "TEST", "https://zora.co/testing/token.json");
        burnTokenERC721.mint(address(tokenRecipient));
        burnTokenERC721.mint(address(tokenRecipient));
        burnTokenERC721.mint(address(tokenRecipient));
        burnTokenERC721.mint(address(tokenRecipient));

        ZoraCreatorRedeemMinterStrategy.MintToken memory mintToken = ZoraCreatorRedeemMinterStrategy.MintToken({
            tokenContract: address(target),
            tokenId: newTokenId,
            amount: 10,
            tokenType: ZoraCreatorRedeemMinterStrategy.TokenType.ERC1155
        });
        ZoraCreatorRedeemMinterStrategy.RedeemInstruction[] memory instructions = new ZoraCreatorRedeemMinterStrategy.RedeemInstruction[](2);
        instructions[0] = ZoraCreatorRedeemMinterStrategy.RedeemInstruction({
            tokenType: ZoraCreatorRedeemMinterStrategy.TokenType.ERC1155,
            amount: 300,
            tokenIdStart: 7,
            tokenIdEnd: 9,
            tokenContract: address(burnTokenERC1155),
            transferRecipient: redeemTokenRecipient,
            burnFunction: 0
        });
        instructions[1] = ZoraCreatorRedeemMinterStrategy.RedeemInstruction({
            tokenType: ZoraCreatorRedeemMinterStrategy.TokenType.ERC721,
            amount: 3,
            tokenIdStart: 1,
            tokenIdEnd: 3,
            tokenContract: address(burnTokenERC721),
            transferRecipient: redeemTokenRecipient,
            burnFunction: 0
        });
        ZoraCreatorRedeemMinterStrategy.RedeemInstructions memory redeemInstructions = ZoraCreatorRedeemMinterStrategy.RedeemInstructions({
            mintToken: mintToken,
            instructions: instructions,
            saleStart: 0,
            saleEnd: type(uint64).max,
            ethAmount: 1 ether,
            ethRecipient: address(0)
        });

        target.callSale(newTokenId, redeemMinter, abi.encodeWithSelector(ZoraCreatorRedeemMinterStrategy.setRedeem.selector, newTokenId, redeemInstructions));
        vm.stopPrank();

        vm.startPrank(tokenRecipient);
        burnTokenERC1155.setApprovalForAll(address(redeemMinter), true);
        burnTokenERC721.setApprovalForAll(address(redeemMinter), true);

        uint256[][] memory tokenIds = new uint256[][](2);
        uint256[][] memory amounts = new uint256[][](2);

        tokenIds[0] = new uint256[](3);
        tokenIds[0][0] = 7;
        tokenIds[0][1] = 8;
        tokenIds[0][2] = 9;
        amounts[0] = new uint256[](3);
        amounts[0][0] = 100;
        amounts[0][1] = 100;
        amounts[0][2] = 100;

        tokenIds[1] = new uint256[](3);
        tokenIds[1][0] = 1;
        tokenIds[1][1] = 2;
        tokenIds[1][2] = 3;

        uint256 totalReward = target.computeTotalReward(target.mintFee(), 10);
        vm.deal(tokenRecipient, 5 ether + totalReward);

        // detour: tokenId out of range
        tokenIds[0][0] = 6;
        vm.expectRevert(abi.encodeWithSignature("TokenIdOutOfRange()"));
        target.mint{value: 1 ether + totalReward}(redeemMinter, newTokenId, 10, rewardRecipients, abi.encode(redeemInstructions, tokenIds, amounts));
        tokenIds[0][0] = 10;
        vm.expectRevert(abi.encodeWithSignature("TokenIdOutOfRange()"));
        target.mint{value: 1 ether + totalReward}(redeemMinter, newTokenId, 10, rewardRecipients, abi.encode(redeemInstructions, tokenIds, amounts));
        tokenIds[0][0] = 7;
        tokenIds[1][0] = 0;
        vm.expectRevert(abi.encodeWithSignature("TokenIdOutOfRange()"));
        target.mint{value: 1 ether + totalReward}(redeemMinter, newTokenId, 10, rewardRecipients, abi.encode(redeemInstructions, tokenIds, amounts));
        tokenIds[1][0] = 4;
        vm.expectRevert(abi.encodeWithSignature("TokenIdOutOfRange()"));
        target.mint{value: 1 ether + totalReward}(redeemMinter, newTokenId, 10, rewardRecipients, abi.encode(redeemInstructions, tokenIds, amounts));
        tokenIds[1][0] = 1;

        target.mint{value: 1 ether + totalReward}(redeemMinter, newTokenId, 10, rewardRecipients, abi.encode(redeemInstructions, tokenIds, amounts));
        assertEq(address(target).balance, 1 ether);
        assertEq(target.balanceOf(tokenRecipient, newTokenId), 10);
        assertEq(burnTokenERC1155.balanceOf(redeemTokenRecipient, 7), 100);
        assertEq(burnTokenERC1155.balanceOf(redeemTokenRecipient, 8), 100);
        assertEq(burnTokenERC1155.balanceOf(redeemTokenRecipient, 9), 100);
        assertEq(burnTokenERC721.balanceOf(redeemTokenRecipient), 3);

        vm.stopPrank();
    }

    function test_MintFlowRedeemStart() external {
        vm.startPrank(admin);

        address tokenRecipient = address(322);
        vm.deal(tokenRecipient, 20 ether);

        ERC20PresetMinterPauser burnToken = new ERC20PresetMinterPauser("Random Token", "RAND");
        burnToken.mint(address(tokenRecipient), 1000);

        ZoraCreatorRedeemMinterStrategy.MintToken memory mintToken = ZoraCreatorRedeemMinterStrategy.MintToken({
            tokenContract: address(target),
            tokenId: newTokenId,
            amount: 10,
            tokenType: ZoraCreatorRedeemMinterStrategy.TokenType.ERC1155
        });
        ZoraCreatorRedeemMinterStrategy.RedeemInstruction[] memory instructions = new ZoraCreatorRedeemMinterStrategy.RedeemInstruction[](1);
        instructions[0] = ZoraCreatorRedeemMinterStrategy.RedeemInstruction({
            tokenType: ZoraCreatorRedeemMinterStrategy.TokenType.ERC20,
            amount: 500,
            tokenIdStart: 0,
            tokenIdEnd: 0,
            tokenContract: address(burnToken),
            transferRecipient: address(0),
            burnFunction: bytes4(keccak256(bytes("burnFrom(address,uint256)")))
        });
        ZoraCreatorRedeemMinterStrategy.RedeemInstructions memory redeemInstructions = ZoraCreatorRedeemMinterStrategy.RedeemInstructions({
            mintToken: mintToken,
            instructions: instructions,
            saleStart: uint64(block.timestamp + 1 days),
            saleEnd: type(uint64).max,
            ethAmount: 1 ether,
            ethRecipient: address(0)
        });

        target.callSale(newTokenId, redeemMinter, abi.encodeWithSelector(ZoraCreatorRedeemMinterStrategy.setRedeem.selector, newTokenId, redeemInstructions));
        vm.stopPrank();

        vm.startPrank(tokenRecipient);
        burnToken.approve(address(redeemMinter), 500);
        uint256[][] memory tokenIds = new uint256[][](1);
        tokenIds[0] = new uint256[](0);
        uint256[][] memory amounts = new uint256[][](1);
        amounts[0] = new uint256[](1);
        amounts[0][0] = 500;
        vm.expectRevert(abi.encodeWithSignature("SaleHasNotStarted()"));
        target.mint{value: 1 ether}(redeemMinter, newTokenId, 1, rewardRecipients, abi.encode(redeemInstructions, tokenIds, amounts));
        vm.stopPrank();
    }

    function test_MintFlowRedeemEnd() external {
        vm.startPrank(admin);

        address tokenRecipient = address(322);
        vm.deal(tokenRecipient, 20 ether);

        ERC20PresetMinterPauser burnToken = new ERC20PresetMinterPauser("Random Token", "RAND");
        burnToken.mint(address(tokenRecipient), 1000);

        ZoraCreatorRedeemMinterStrategy.MintToken memory mintToken = ZoraCreatorRedeemMinterStrategy.MintToken({
            tokenContract: address(target),
            tokenId: newTokenId,
            amount: 10,
            tokenType: ZoraCreatorRedeemMinterStrategy.TokenType.ERC1155
        });
        ZoraCreatorRedeemMinterStrategy.RedeemInstruction[] memory instructions = new ZoraCreatorRedeemMinterStrategy.RedeemInstruction[](1);
        instructions[0] = ZoraCreatorRedeemMinterStrategy.RedeemInstruction({
            tokenType: ZoraCreatorRedeemMinterStrategy.TokenType.ERC20,
            amount: 500,
            tokenIdStart: 0,
            tokenIdEnd: 0,
            tokenContract: address(burnToken),
            transferRecipient: address(0),
            burnFunction: bytes4(keccak256(bytes("burnFrom(address,uint256)")))
        });
        ZoraCreatorRedeemMinterStrategy.RedeemInstructions memory redeemInstructions = ZoraCreatorRedeemMinterStrategy.RedeemInstructions({
            mintToken: mintToken,
            instructions: instructions,
            saleStart: 0,
            saleEnd: uint64(1 days),
            ethAmount: 1 ether,
            ethRecipient: address(0)
        });

        target.callSale(newTokenId, redeemMinter, abi.encodeWithSelector(ZoraCreatorRedeemMinterStrategy.setRedeem.selector, newTokenId, redeemInstructions));
        vm.stopPrank();

        vm.warp(2 days);

        vm.startPrank(tokenRecipient);
        burnToken.approve(address(redeemMinter), 1000);
        uint256[] memory tokenIds = new uint256[](0);
        uint256[][] memory amounts = new uint256[][](1);
        amounts[0] = new uint256[](1);
        amounts[0][0] = 500;
        vm.expectRevert(abi.encodeWithSignature("SaleEnded()"));
        target.mint{value: 1 ether}(redeemMinter, newTokenId, 1, rewardRecipients, abi.encode(redeemInstructions, tokenIds, amounts));
        vm.stopPrank();
    }

    function test_MintFlowEthValue() external {
        vm.startPrank(admin);

        address tokenRecipient = address(322);
        vm.deal(tokenRecipient, 20 ether);

        ERC20PresetMinterPauser burnToken = new ERC20PresetMinterPauser("Random Token", "RAND");
        burnToken.mint(address(tokenRecipient), 1000);

        ZoraCreatorRedeemMinterStrategy.MintToken memory mintToken = ZoraCreatorRedeemMinterStrategy.MintToken({
            tokenContract: address(target),
            tokenId: newTokenId,
            amount: 10,
            tokenType: ZoraCreatorRedeemMinterStrategy.TokenType.ERC1155
        });
        ZoraCreatorRedeemMinterStrategy.RedeemInstruction[] memory instructions = new ZoraCreatorRedeemMinterStrategy.RedeemInstruction[](1);
        instructions[0] = ZoraCreatorRedeemMinterStrategy.RedeemInstruction({
            tokenType: ZoraCreatorRedeemMinterStrategy.TokenType.ERC20,
            amount: 500,
            tokenIdStart: 0,
            tokenIdEnd: 0,
            tokenContract: address(burnToken),
            transferRecipient: address(0),
            burnFunction: bytes4(keccak256(bytes("burnFrom(address,uint256)")))
        });
        ZoraCreatorRedeemMinterStrategy.RedeemInstructions memory redeemInstructions = ZoraCreatorRedeemMinterStrategy.RedeemInstructions({
            mintToken: mintToken,
            instructions: instructions,
            saleStart: 0,
            saleEnd: type(uint64).max,
            ethAmount: 1 ether,
            ethRecipient: address(0)
        });

        target.callSale(newTokenId, redeemMinter, abi.encodeWithSelector(ZoraCreatorRedeemMinterStrategy.setRedeem.selector, newTokenId, redeemInstructions));
        vm.stopPrank();

        vm.startPrank(tokenRecipient);
        burnToken.approve(address(redeemMinter), 500);
        uint256[][] memory tokenIds = new uint256[][](1);
        tokenIds[0] = new uint256[](0);
        uint256[][] memory amounts = new uint256[][](1);
        amounts[0] = new uint256[](1);
        amounts[0][0] = 500;

        uint256 totalReward = target.computeTotalReward(target.mintFee(), 10);
        vm.deal(tokenRecipient, 3 ether + totalReward);

        vm.expectRevert(abi.encodeWithSignature("WrongValueSent()"));
        target.mint{value: 0.9 ether + totalReward}(redeemMinter, newTokenId, 10, rewardRecipients, abi.encode(redeemInstructions, tokenIds, amounts));
        vm.expectRevert(abi.encodeWithSignature("WrongValueSent()"));
        target.mint{value: 1.1 ether + totalReward}(redeemMinter, newTokenId, 10, rewardRecipients, abi.encode(redeemInstructions, tokenIds, amounts));

        target.mint{value: 1 ether + totalReward}(redeemMinter, newTokenId, 10, rewardRecipients, abi.encode(redeemInstructions, tokenIds, amounts));
        vm.stopPrank();
    }

    function test_MintFlowFundsRecipient() external {
        vm.startPrank(admin);

        address fundsRecipient = address(239);
        address tokenRecipient = address(322);
        vm.deal(tokenRecipient, 20 ether);

        ERC20PresetMinterPauser burnToken = new ERC20PresetMinterPauser("Random Token", "RAND");
        burnToken.mint(address(tokenRecipient), 1000);

        ZoraCreatorRedeemMinterStrategy.MintToken memory mintToken = ZoraCreatorRedeemMinterStrategy.MintToken({
            tokenContract: address(target),
            tokenId: newTokenId,
            amount: 10,
            tokenType: ZoraCreatorRedeemMinterStrategy.TokenType.ERC1155
        });
        ZoraCreatorRedeemMinterStrategy.RedeemInstruction[] memory instructions = new ZoraCreatorRedeemMinterStrategy.RedeemInstruction[](1);
        instructions[0] = ZoraCreatorRedeemMinterStrategy.RedeemInstruction({
            tokenType: ZoraCreatorRedeemMinterStrategy.TokenType.ERC20,
            amount: 500,
            tokenIdStart: 0,
            tokenIdEnd: 0,
            tokenContract: address(burnToken),
            transferRecipient: address(0),
            burnFunction: bytes4(keccak256(bytes("burnFrom(address,uint256)")))
        });
        ZoraCreatorRedeemMinterStrategy.RedeemInstructions memory redeemInstructions = ZoraCreatorRedeemMinterStrategy.RedeemInstructions({
            mintToken: mintToken,
            instructions: instructions,
            saleStart: 0,
            saleEnd: type(uint64).max,
            ethAmount: 1 ether,
            ethRecipient: fundsRecipient
        });

        target.callSale(newTokenId, redeemMinter, abi.encodeWithSelector(ZoraCreatorRedeemMinterStrategy.setRedeem.selector, newTokenId, redeemInstructions));
        vm.stopPrank();

        vm.startPrank(tokenRecipient);
        burnToken.approve(address(redeemMinter), 500);
        uint256[][] memory tokenIds = new uint256[][](1);
        tokenIds[0] = new uint256[](0);
        uint256[][] memory amounts = new uint256[][](1);
        amounts[0] = new uint256[](1);
        amounts[0][0] = 500;

        uint256 totalReward = target.computeTotalReward(target.mintFee(), 10);
        vm.deal(tokenRecipient, 1 ether + totalReward);

        target.mint{value: 1 ether + totalReward}(redeemMinter, newTokenId, 10, rewardRecipients, abi.encode(redeemInstructions, tokenIds, amounts));
        assertEq(fundsRecipient.balance, 1 ether);
        vm.stopPrank();
    }

    function testRevert_IncorrectMintTokenAmount() external {
        vm.startPrank(admin);

        address tokenRecipient = address(322);
        vm.deal(tokenRecipient, 20 ether);

        ERC20PresetMinterPauser burnToken = new ERC20PresetMinterPauser("Random Token", "RAND");
        burnToken.mint(address(tokenRecipient), 1000);

        ZoraCreatorRedeemMinterStrategy.MintToken memory mintToken = ZoraCreatorRedeemMinterStrategy.MintToken({
            tokenContract: address(target),
            tokenId: newTokenId,
            amount: 10,
            tokenType: ZoraCreatorRedeemMinterStrategy.TokenType.ERC1155
        });
        ZoraCreatorRedeemMinterStrategy.RedeemInstruction[] memory instructions = new ZoraCreatorRedeemMinterStrategy.RedeemInstruction[](1);
        instructions[0] = ZoraCreatorRedeemMinterStrategy.RedeemInstruction({
            tokenType: ZoraCreatorRedeemMinterStrategy.TokenType.ERC20,
            amount: 500,
            tokenIdStart: 0,
            tokenIdEnd: 0,
            tokenContract: address(burnToken),
            transferRecipient: address(0),
            burnFunction: bytes4(keccak256(bytes("burnFrom(address,uint256)")))
        });
        ZoraCreatorRedeemMinterStrategy.RedeemInstructions memory redeemInstructions = ZoraCreatorRedeemMinterStrategy.RedeemInstructions({
            mintToken: mintToken,
            instructions: instructions,
            saleStart: 0,
            saleEnd: type(uint64).max,
            ethAmount: 1 ether,
            ethRecipient: address(0)
        });

        target.callSale(newTokenId, redeemMinter, abi.encodeWithSelector(ZoraCreatorRedeemMinterStrategy.setRedeem.selector, newTokenId, redeemInstructions));
        vm.stopPrank();

        vm.startPrank(tokenRecipient);
        burnToken.approve(address(redeemMinter), 500);
        uint256[][] memory tokenIds = new uint256[][](1);
        tokenIds[0] = new uint256[](0);
        uint256[][] memory amounts = new uint256[][](1);
        amounts[0] = new uint256[](1);
        amounts[0][0] = 500;

        uint256 incorrectNumTokens = 11;
        uint256 totalReward = target.computeTotalReward(target.mintFee(), incorrectNumTokens);
        vm.deal(tokenRecipient, 1 ether + totalReward);

        vm.expectRevert(abi.encodeWithSignature("IncorrectMintAmount()"));
        target.mint{value: 1 ether + totalReward}(
            redeemMinter,
            newTokenId,
            incorrectNumTokens,
            rewardRecipients,
            abi.encode(redeemInstructions, tokenIds, amounts)
        );
        vm.stopPrank();
    }

    function test_MintFlowIncorrectNumberOfTokenIds() external {
        vm.startPrank(admin);

        address tokenRecipient = address(322);
        vm.deal(tokenRecipient, 20 ether);

        ERC1155PresetMinterPauser burnToken = new ERC1155PresetMinterPauser("https://zora.co/testing/token.json");
        burnToken.mint(address(tokenRecipient), 1, 1000, "");

        ZoraCreatorRedeemMinterStrategy.MintToken memory mintToken = ZoraCreatorRedeemMinterStrategy.MintToken({
            tokenContract: address(target),
            tokenId: newTokenId,
            amount: 10,
            tokenType: ZoraCreatorRedeemMinterStrategy.TokenType.ERC1155
        });
        ZoraCreatorRedeemMinterStrategy.RedeemInstruction[] memory instructions = new ZoraCreatorRedeemMinterStrategy.RedeemInstruction[](1);
        instructions[0] = ZoraCreatorRedeemMinterStrategy.RedeemInstruction({
            tokenType: ZoraCreatorRedeemMinterStrategy.TokenType.ERC1155,
            amount: 500,
            tokenIdStart: 1,
            tokenIdEnd: 1,
            tokenContract: address(burnToken),
            transferRecipient: address(0),
            burnFunction: bytes4(keccak256(bytes("burnBatch(address,uint256[],uint256[])")))
        });
        ZoraCreatorRedeemMinterStrategy.RedeemInstructions memory redeemInstructions = ZoraCreatorRedeemMinterStrategy.RedeemInstructions({
            mintToken: mintToken,
            instructions: instructions,
            saleStart: 0,
            saleEnd: type(uint64).max,
            ethAmount: 1 ether,
            ethRecipient: address(0)
        });

        target.callSale(newTokenId, redeemMinter, abi.encodeWithSelector(ZoraCreatorRedeemMinterStrategy.setRedeem.selector, newTokenId, redeemInstructions));
        vm.stopPrank();

        // instructions length != tokenIds length
        vm.startPrank(tokenRecipient);
        burnToken.setApprovalForAll(address(redeemMinter), true);
        uint256[][] memory tokenIds = new uint256[][](2);
        uint256[][] memory amounts = new uint256[][](1);
        amounts[0] = new uint256[](1);
        amounts[0][0] = 500;
        vm.expectRevert(abi.encodeWithSignature("IncorrectNumberOfTokenIds()"));
        target.mint{value: 1 ether}(redeemMinter, newTokenId, 10, rewardRecipients, abi.encode(redeemInstructions, tokenIds, amounts));
        tokenIds = new uint256[][](1);
        tokenIds[0] = new uint256[](1);
        tokenIds[0][0] = 1;

        // ERC1155: amounts length != tokenIds length
        amounts = new uint256[][](2);

        uint256 totalReward = target.computeTotalReward(target.mintFee(), 10);
        vm.deal(tokenRecipient, 1 ether + totalReward);

        vm.expectRevert(abi.encodeWithSignature("IncorrectNumberOfTokenIds()"));
        target.mint{value: 1 ether + totalReward}(redeemMinter, newTokenId, 10, rewardRecipients, abi.encode(redeemInstructions, tokenIds, amounts));
    }

    function test_MintFlowIncorrectBurnOrTransferAmount() external {
        vm.startPrank(admin);

        address tokenRecipient = address(322);
        vm.deal(tokenRecipient, 20 ether);
        address redeemTokenRecipient = address(323);

        ERC1155PresetMinterPauser burnTokenERC1155 = new ERC1155PresetMinterPauser("https://zora.co/testing/token.json");
        burnTokenERC1155.mint(address(tokenRecipient), 1, 500, "");
        ERC721PresetMinterPauserAutoId burnTokenERC721 = new ERC721PresetMinterPauserAutoId("Test token", "TEST", "https://zora.co/testing/token.json");
        burnTokenERC721.mint(address(tokenRecipient));
        burnTokenERC721.mint(address(tokenRecipient));

        ZoraCreatorRedeemMinterStrategy.MintToken memory mintToken = ZoraCreatorRedeemMinterStrategy.MintToken({
            tokenContract: address(target),
            tokenId: newTokenId,
            amount: 10,
            tokenType: ZoraCreatorRedeemMinterStrategy.TokenType.ERC1155
        });
        ZoraCreatorRedeemMinterStrategy.RedeemInstruction[] memory instructions = new ZoraCreatorRedeemMinterStrategy.RedeemInstruction[](2);
        instructions[0] = ZoraCreatorRedeemMinterStrategy.RedeemInstruction({
            tokenType: ZoraCreatorRedeemMinterStrategy.TokenType.ERC1155,
            amount: 300,
            tokenIdStart: 1,
            tokenIdEnd: 1,
            tokenContract: address(burnTokenERC1155),
            transferRecipient: redeemTokenRecipient,
            burnFunction: 0
        });
        instructions[1] = ZoraCreatorRedeemMinterStrategy.RedeemInstruction({
            tokenType: ZoraCreatorRedeemMinterStrategy.TokenType.ERC721,
            amount: 3,
            tokenIdStart: 0,
            tokenIdEnd: 2,
            tokenContract: address(burnTokenERC721),
            transferRecipient: redeemTokenRecipient,
            burnFunction: 0
        });
        ZoraCreatorRedeemMinterStrategy.RedeemInstructions memory redeemInstructions = ZoraCreatorRedeemMinterStrategy.RedeemInstructions({
            mintToken: mintToken,
            instructions: instructions,
            saleStart: 0,
            saleEnd: type(uint64).max,
            ethAmount: 1 ether,
            ethRecipient: address(0)
        });

        target.callSale(newTokenId, redeemMinter, abi.encodeWithSelector(ZoraCreatorRedeemMinterStrategy.setRedeem.selector, newTokenId, redeemInstructions));
        vm.stopPrank();

        vm.startPrank(tokenRecipient);
        burnTokenERC1155.setApprovalForAll(address(redeemMinter), true);
        burnTokenERC721.setApprovalForAll(address(redeemMinter), true);

        uint256[][] memory tokenIds = new uint256[][](2);
        uint256[][] memory amounts = new uint256[][](2);

        // this would be correct
        tokenIds[0] = new uint256[](1);
        tokenIds[0][0] = 1;
        amounts[0] = new uint256[](1);
        amounts[0][0] = 500;
        tokenIds[1] = new uint256[](2);
        tokenIds[1][0] = 0;
        tokenIds[1][1] = 1;

        uint256 totalReward = target.computeTotalReward(target.mintFee(), 10);
        vm.deal(tokenRecipient, 4 ether + totalReward);

        // ERC721: tokenids length != instruction amount
        tokenIds[1] = new uint256[](1);
        vm.expectRevert(abi.encodeWithSignature("IncorrectBurnOrTransferAmount()"));
        target.mint{value: 1 ether + totalReward}(redeemMinter, newTokenId, 10, rewardRecipients, abi.encode(redeemInstructions, tokenIds, amounts));
        tokenIds[1] = new uint256[](3);
        vm.expectRevert(abi.encodeWithSignature("IncorrectBurnOrTransferAmount()"));
        target.mint{value: 1 ether + totalReward}(redeemMinter, newTokenId, 10, rewardRecipients, abi.encode(redeemInstructions, tokenIds, amounts));
        tokenIds[1] = new uint256[](2);
        tokenIds[1][0] = 0;
        tokenIds[1][1] = 1;

        // ERC1155: sum of amounts != instruction amount
        amounts[0][0] = 499;
        vm.expectRevert(abi.encodeWithSignature("IncorrectBurnOrTransferAmount()"));
        target.mint{value: 1 ether + totalReward}(redeemMinter, newTokenId, 10, rewardRecipients, abi.encode(redeemInstructions, tokenIds, amounts));
        amounts[0][0] = 501;
        vm.expectRevert(abi.encodeWithSignature("IncorrectBurnOrTransferAmount()"));
        target.mint{value: 1 ether + totalReward}(redeemMinter, newTokenId, 10, rewardRecipients, abi.encode(redeemInstructions, tokenIds, amounts));

        vm.stopPrank();
    }

    function test_MintFlowSenderNotTokenOwnerBurn20() external {
        vm.startPrank(admin);

        address actualTokenOwner = address(92834);

        address tokenRecipient = address(322);
        vm.deal(tokenRecipient, 20 ether);

        ERC20PresetMinterPauser burnTokenERC20 = new ERC20PresetMinterPauser("Random Token", "RAND");
        burnTokenERC20.mint(address(actualTokenOwner), 1000);
        ERC1155PresetMinterPauser burnTokenERC1155 = new ERC1155PresetMinterPauser("https://zora.co/testing/token.json");
        burnTokenERC1155.mint(address(actualTokenOwner), 1, 1000, "");
        ERC721PresetMinterPauserAutoId burnTokenERC721 = new ERC721PresetMinterPauserAutoId("Test token", "TEST", "https://zora.co/testing/token.json");
        burnTokenERC721.mint(address(actualTokenOwner));
        burnTokenERC721.mint(address(actualTokenOwner));

        ZoraCreatorRedeemMinterStrategy.MintToken memory mintToken = ZoraCreatorRedeemMinterStrategy.MintToken({
            tokenContract: address(target),
            tokenId: newTokenId,
            amount: 10,
            tokenType: ZoraCreatorRedeemMinterStrategy.TokenType.ERC1155
        });
        ZoraCreatorRedeemMinterStrategy.RedeemInstruction[] memory instructions = new ZoraCreatorRedeemMinterStrategy.RedeemInstruction[](1);
        instructions[0] = ZoraCreatorRedeemMinterStrategy.RedeemInstruction({
            tokenType: ZoraCreatorRedeemMinterStrategy.TokenType.ERC20,
            amount: 500,
            tokenIdStart: 0,
            tokenIdEnd: 0,
            tokenContract: address(burnTokenERC20),
            transferRecipient: address(0),
            burnFunction: bytes4(keccak256(bytes("burnFrom(address,uint256)")))
        });
        ZoraCreatorRedeemMinterStrategy.RedeemInstructions memory redeemInstructions = ZoraCreatorRedeemMinterStrategy.RedeemInstructions({
            mintToken: mintToken,
            instructions: instructions,
            saleStart: 0,
            saleEnd: type(uint64).max,
            ethAmount: 1 ether,
            ethRecipient: address(0)
        });

        target.callSale(newTokenId, redeemMinter, abi.encodeWithSelector(ZoraCreatorRedeemMinterStrategy.setRedeem.selector, newTokenId, redeemInstructions));
        vm.stopPrank();

        vm.startPrank(tokenRecipient);
        burnTokenERC20.approve(address(redeemMinter), 500);

        uint256[][] memory tokenIds = new uint256[][](1);
        uint256[][] memory amounts = new uint256[][](1);
        amounts[0] = new uint256[](1);
        amounts[0][0] = 500;

        uint256 totalReward = target.computeTotalReward(target.mintFee(), 10);
        vm.deal(tokenRecipient, 1 ether + totalReward);

        vm.expectRevert(abi.encodeWithSignature("BurnFailed()"));
        target.mint{value: 1 ether + totalReward}(redeemMinter, newTokenId, 10, rewardRecipients, abi.encode(redeemInstructions, tokenIds, amounts));
        vm.stopPrank();
    }

    function test_MintFlowSenderNotTokenOwnerBurn1155() external {
        vm.startPrank(admin);

        address actualTokenOwner = address(92834);

        address tokenRecipient = address(322);
        vm.deal(tokenRecipient, 20 ether);

        ERC20PresetMinterPauser burnTokenERC20 = new ERC20PresetMinterPauser("Random Token", "RAND");
        burnTokenERC20.mint(address(actualTokenOwner), 1000);
        ERC1155PresetMinterPauser burnTokenERC1155 = new ERC1155PresetMinterPauser("https://zora.co/testing/token.json");
        burnTokenERC1155.mint(address(actualTokenOwner), 1, 1000, "");
        ERC721PresetMinterPauserAutoId burnTokenERC721 = new ERC721PresetMinterPauserAutoId("Test token", "TEST", "https://zora.co/testing/token.json");
        burnTokenERC721.mint(address(actualTokenOwner));
        burnTokenERC721.mint(address(actualTokenOwner));

        ZoraCreatorRedeemMinterStrategy.MintToken memory mintToken = ZoraCreatorRedeemMinterStrategy.MintToken({
            tokenContract: address(target),
            tokenId: newTokenId,
            amount: 10,
            tokenType: ZoraCreatorRedeemMinterStrategy.TokenType.ERC1155
        });

        ZoraCreatorRedeemMinterStrategy.RedeemInstruction[] memory instructions = new ZoraCreatorRedeemMinterStrategy.RedeemInstruction[](1);
        instructions[0] = ZoraCreatorRedeemMinterStrategy.RedeemInstruction({
            tokenType: ZoraCreatorRedeemMinterStrategy.TokenType.ERC1155,
            amount: 500,
            tokenIdStart: 1,
            tokenIdEnd: 1,
            tokenContract: address(burnTokenERC1155),
            transferRecipient: address(0),
            burnFunction: bytes4(keccak256(bytes("burnBatch(address,uint256[],uint256[])")))
        });
        ZoraCreatorRedeemMinterStrategy.RedeemInstructions memory redeemInstructions = ZoraCreatorRedeemMinterStrategy.RedeemInstructions({
            mintToken: mintToken,
            instructions: instructions,
            saleStart: 0,
            saleEnd: type(uint64).max,
            ethAmount: 1 ether,
            ethRecipient: address(0)
        });

        target.callSale(newTokenId, redeemMinter, abi.encodeWithSelector(ZoraCreatorRedeemMinterStrategy.setRedeem.selector, newTokenId, redeemInstructions));
        vm.stopPrank();

        vm.startPrank(tokenRecipient);
        burnTokenERC1155.setApprovalForAll(address(redeemMinter), true);

        uint256[][] memory tokenIds = new uint256[][](1);
        tokenIds[0] = new uint256[](1);
        tokenIds[0][0] = 1;
        uint256[][] memory amounts = new uint256[][](1);
        amounts[0] = new uint256[](1);
        amounts[0][0] = 500;

        uint256 totalReward = target.computeTotalReward(target.mintFee(), 10);
        vm.deal(tokenRecipient, 1 ether + totalReward);

        vm.expectRevert(abi.encodeWithSignature("BurnFailed()"));
        target.mint{value: 1 ether + totalReward}(redeemMinter, newTokenId, 10, rewardRecipients, abi.encode(redeemInstructions, tokenIds, amounts));
        vm.stopPrank();
    }

    function test_MintFlowSenderNotTokenOwnerBurn721() external {
        vm.startPrank(admin);

        address actualTokenOwner = address(92834);

        address tokenRecipient = address(322);
        vm.deal(tokenRecipient, 20 ether);

        ERC20PresetMinterPauser burnTokenERC20 = new ERC20PresetMinterPauser("Random Token", "RAND");
        burnTokenERC20.mint(address(actualTokenOwner), 1000);
        ERC1155PresetMinterPauser burnTokenERC1155 = new ERC1155PresetMinterPauser("https://zora.co/testing/token.json");
        burnTokenERC1155.mint(address(actualTokenOwner), 1, 1000, "");
        ERC721PresetMinterPauserAutoId burnTokenERC721 = new ERC721PresetMinterPauserAutoId("Test token", "TEST", "https://zora.co/testing/token.json");
        burnTokenERC721.mint(address(actualTokenOwner));
        burnTokenERC721.mint(address(actualTokenOwner));

        ZoraCreatorRedeemMinterStrategy.MintToken memory mintToken = ZoraCreatorRedeemMinterStrategy.MintToken({
            tokenContract: address(target),
            tokenId: newTokenId,
            amount: 10,
            tokenType: ZoraCreatorRedeemMinterStrategy.TokenType.ERC1155
        });

        ZoraCreatorRedeemMinterStrategy.RedeemInstruction[] memory instructions = new ZoraCreatorRedeemMinterStrategy.RedeemInstruction[](1);
        instructions[0] = ZoraCreatorRedeemMinterStrategy.RedeemInstruction({
            tokenType: ZoraCreatorRedeemMinterStrategy.TokenType.ERC721,
            amount: 2,
            tokenIdStart: 0,
            tokenIdEnd: 1,
            tokenContract: address(burnTokenERC721),
            transferRecipient: address(0),
            burnFunction: bytes4(keccak256(bytes("burn(uint256)")))
        });
        ZoraCreatorRedeemMinterStrategy.RedeemInstructions memory redeemInstructions = ZoraCreatorRedeemMinterStrategy.RedeemInstructions({
            mintToken: mintToken,
            instructions: instructions,
            saleStart: 0,
            saleEnd: type(uint64).max,
            ethAmount: 1 ether,
            ethRecipient: address(0)
        });

        target.callSale(newTokenId, redeemMinter, abi.encodeWithSelector(ZoraCreatorRedeemMinterStrategy.setRedeem.selector, newTokenId, redeemInstructions));
        vm.stopPrank();

        vm.prank(actualTokenOwner);
        burnTokenERC721.setApprovalForAll(address(redeemMinter), true);
        vm.startPrank(tokenRecipient);
        burnTokenERC721.setApprovalForAll(address(redeemMinter), true);

        uint256[][] memory tokenIds = new uint256[][](1);
        tokenIds[0] = new uint256[](2);
        tokenIds[0][0] = 0;
        tokenIds[0][1] = 1;
        uint256[][] memory amounts;

        uint256 totalReward = target.computeTotalReward(target.mintFee(), 10);
        vm.deal(tokenRecipient, 1 ether + totalReward);

        vm.expectRevert(abi.encodeWithSignature("SenderIsNotTokenOwner()"));
        target.mint{value: 1 ether + totalReward}(redeemMinter, newTokenId, 10, rewardRecipients, abi.encode(redeemInstructions, tokenIds, amounts));
        vm.stopPrank();
    }

    function test_MintFlowSenderNotTokenOwnerTransfer20() external {
        vm.startPrank(admin);

        address actualTokenOwner = address(92834);

        address tokenRecipient = address(322);
        vm.deal(tokenRecipient, 20 ether);

        ERC20PresetMinterPauser burnTokenERC20 = new ERC20PresetMinterPauser("Random Token", "RAND");
        burnTokenERC20.mint(address(actualTokenOwner), 1000);
        ERC1155PresetMinterPauser burnTokenERC1155 = new ERC1155PresetMinterPauser("https://zora.co/testing/token.json");
        burnTokenERC1155.mint(address(actualTokenOwner), 1, 1000, "");
        ERC721PresetMinterPauserAutoId burnTokenERC721 = new ERC721PresetMinterPauserAutoId("Test token", "TEST", "https://zora.co/testing/token.json");
        burnTokenERC721.mint(address(actualTokenOwner));
        burnTokenERC721.mint(address(actualTokenOwner));

        ZoraCreatorRedeemMinterStrategy.MintToken memory mintToken = ZoraCreatorRedeemMinterStrategy.MintToken({
            tokenContract: address(target),
            tokenId: newTokenId,
            amount: 10,
            tokenType: ZoraCreatorRedeemMinterStrategy.TokenType.ERC1155
        });

        ZoraCreatorRedeemMinterStrategy.RedeemInstruction[] memory instructions = new ZoraCreatorRedeemMinterStrategy.RedeemInstruction[](1);
        instructions[0] = ZoraCreatorRedeemMinterStrategy.RedeemInstruction({
            tokenType: ZoraCreatorRedeemMinterStrategy.TokenType.ERC20,
            amount: 500,
            tokenIdStart: 0,
            tokenIdEnd: 0,
            tokenContract: address(burnTokenERC20),
            transferRecipient: address(1),
            burnFunction: bytes4(0)
        });
        ZoraCreatorRedeemMinterStrategy.RedeemInstructions memory redeemInstructions = ZoraCreatorRedeemMinterStrategy.RedeemInstructions({
            mintToken: mintToken,
            instructions: instructions,
            saleStart: 0,
            saleEnd: type(uint64).max,
            ethAmount: 1 ether,
            ethRecipient: address(0)
        });

        target.callSale(newTokenId, redeemMinter, abi.encodeWithSelector(ZoraCreatorRedeemMinterStrategy.setRedeem.selector, newTokenId, redeemInstructions));
        vm.stopPrank();

        vm.startPrank(tokenRecipient);
        burnTokenERC20.approve(address(redeemMinter), 500);

        uint256[][] memory tokenIds = new uint256[][](1);
        uint256[][] memory amounts = new uint256[][](1);
        amounts[0] = new uint256[](1);
        amounts[0][0] = 500;

        uint256 totalReward = target.computeTotalReward(target.mintFee(), 10);
        vm.deal(tokenRecipient, 1 ether + totalReward);

        vm.expectRevert("ERC20: transfer amount exceeds balance");
        target.mint{value: 1 ether + totalReward}(redeemMinter, newTokenId, 10, rewardRecipients, abi.encode(redeemInstructions, tokenIds, amounts));
        vm.stopPrank();
    }

    function test_MintFlowSenderNotTokenOwnerTransfer1155() external {
        vm.startPrank(admin);

        address actualTokenOwner = address(92834);

        address tokenRecipient = address(322);
        vm.deal(tokenRecipient, 20 ether);

        ERC20PresetMinterPauser burnTokenERC20 = new ERC20PresetMinterPauser("Random Token", "RAND");
        burnTokenERC20.mint(address(actualTokenOwner), 1000);
        ERC1155PresetMinterPauser burnTokenERC1155 = new ERC1155PresetMinterPauser("https://zora.co/testing/token.json");
        burnTokenERC1155.mint(address(actualTokenOwner), 1, 1000, "");
        ERC721PresetMinterPauserAutoId burnTokenERC721 = new ERC721PresetMinterPauserAutoId("Test token", "TEST", "https://zora.co/testing/token.json");
        burnTokenERC721.mint(address(actualTokenOwner));
        burnTokenERC721.mint(address(actualTokenOwner));

        ZoraCreatorRedeemMinterStrategy.MintToken memory mintToken = ZoraCreatorRedeemMinterStrategy.MintToken({
            tokenContract: address(target),
            tokenId: newTokenId,
            amount: 10,
            tokenType: ZoraCreatorRedeemMinterStrategy.TokenType.ERC1155
        });

        ZoraCreatorRedeemMinterStrategy.RedeemInstruction[] memory instructions = new ZoraCreatorRedeemMinterStrategy.RedeemInstruction[](1);
        instructions[0] = ZoraCreatorRedeemMinterStrategy.RedeemInstruction({
            tokenType: ZoraCreatorRedeemMinterStrategy.TokenType.ERC1155,
            amount: 500,
            tokenIdStart: 1,
            tokenIdEnd: 1,
            tokenContract: address(burnTokenERC1155),
            transferRecipient: address(1),
            burnFunction: bytes4(0)
        });
        ZoraCreatorRedeemMinterStrategy.RedeemInstructions memory redeemInstructions = ZoraCreatorRedeemMinterStrategy.RedeemInstructions({
            mintToken: mintToken,
            instructions: instructions,
            saleStart: 0,
            saleEnd: type(uint64).max,
            ethAmount: 1 ether,
            ethRecipient: address(0)
        });

        target.callSale(newTokenId, redeemMinter, abi.encodeWithSelector(ZoraCreatorRedeemMinterStrategy.setRedeem.selector, newTokenId, redeemInstructions));
        vm.stopPrank();

        vm.startPrank(tokenRecipient);
        burnTokenERC1155.setApprovalForAll(address(redeemMinter), true);

        uint256[][] memory tokenIds = new uint256[][](1);
        tokenIds[0] = new uint256[](1);
        tokenIds[0][0] = 1;
        uint256[][] memory amounts = new uint256[][](1);
        amounts[0] = new uint256[](1);
        amounts[0][0] = 500;

        uint256 totalReward = target.computeTotalReward(target.mintFee(), 10);
        vm.deal(tokenRecipient, 1 ether + totalReward);

        vm.expectRevert("ERC1155: insufficient balance for transfer");
        target.mint{value: 1 ether + totalReward}(redeemMinter, newTokenId, 10, rewardRecipients, abi.encode(redeemInstructions, tokenIds, amounts));
        vm.stopPrank();
    }

    function test_MintFlowSenderNotTokenOwnerTransfer721() external {
        vm.startPrank(admin);

        address actualTokenOwner = address(92834);

        address tokenRecipient = address(322);
        vm.deal(tokenRecipient, 20 ether);

        ERC20PresetMinterPauser burnTokenERC20 = new ERC20PresetMinterPauser("Random Token", "RAND");
        burnTokenERC20.mint(address(actualTokenOwner), 1000);
        ERC1155PresetMinterPauser burnTokenERC1155 = new ERC1155PresetMinterPauser("https://zora.co/testing/token.json");
        burnTokenERC1155.mint(address(actualTokenOwner), 1, 1000, "");
        ERC721PresetMinterPauserAutoId burnTokenERC721 = new ERC721PresetMinterPauserAutoId("Test token", "TEST", "https://zora.co/testing/token.json");
        burnTokenERC721.mint(address(actualTokenOwner));
        burnTokenERC721.mint(address(actualTokenOwner));

        ZoraCreatorRedeemMinterStrategy.MintToken memory mintToken = ZoraCreatorRedeemMinterStrategy.MintToken({
            tokenContract: address(target),
            tokenId: newTokenId,
            amount: 10,
            tokenType: ZoraCreatorRedeemMinterStrategy.TokenType.ERC1155
        });

        ZoraCreatorRedeemMinterStrategy.RedeemInstruction[] memory instructions = new ZoraCreatorRedeemMinterStrategy.RedeemInstruction[](1);
        instructions[0] = ZoraCreatorRedeemMinterStrategy.RedeemInstruction({
            tokenType: ZoraCreatorRedeemMinterStrategy.TokenType.ERC721,
            amount: 2,
            tokenIdStart: 0,
            tokenIdEnd: 1,
            tokenContract: address(burnTokenERC721),
            transferRecipient: address(1),
            burnFunction: bytes4(0)
        });
        ZoraCreatorRedeemMinterStrategy.RedeemInstructions memory redeemInstructions = ZoraCreatorRedeemMinterStrategy.RedeemInstructions({
            mintToken: mintToken,
            instructions: instructions,
            saleStart: 0,
            saleEnd: type(uint64).max,
            ethAmount: 1 ether,
            ethRecipient: address(0)
        });

        target.callSale(newTokenId, redeemMinter, abi.encodeWithSelector(ZoraCreatorRedeemMinterStrategy.setRedeem.selector, newTokenId, redeemInstructions));
        vm.stopPrank();

        vm.startPrank(tokenRecipient);
        burnTokenERC721.setApprovalForAll(address(redeemMinter), true);

        uint256[][] memory tokenIds = new uint256[][](1);
        tokenIds[0] = new uint256[](2);
        tokenIds[0][0] = 0;
        tokenIds[0][1] = 1;
        uint256[][] memory amounts;

        uint256 totalReward = target.computeTotalReward(target.mintFee(), 10);
        vm.deal(tokenRecipient, 1 ether + totalReward);

        vm.expectRevert("ERC721: caller is not token owner or approved");
        target.mint{value: 1 ether + totalReward}(redeemMinter, newTokenId, 10, rewardRecipients, abi.encode(redeemInstructions, tokenIds, amounts));
        vm.stopPrank();
    }

    ///////// RESET AND CLEAR /////////

    function test_ResetSaleAlwaysReverts() external {
        vm.prank(address(target));
        vm.expectRevert(abi.encodeWithSignature("MustCallClearRedeem()"));
        redeemMinter.resetSale(uint256(1));
    }

    function test_ClearRedeem() external {
        vm.startPrank(admin);

        address tokenRecipient = address(322);
        vm.deal(tokenRecipient, 20 ether);

        ERC721PresetMinterPauserAutoId burnToken = new ERC721PresetMinterPauserAutoId("Test token", "TEST", "https://zora.co/testing/token.json");
        burnToken.mint(address(tokenRecipient));
        burnToken.mint(address(tokenRecipient));

        ZoraCreatorRedeemMinterStrategy.MintToken memory mintToken = ZoraCreatorRedeemMinterStrategy.MintToken({
            tokenContract: address(target),
            tokenId: newTokenId,
            amount: 10,
            tokenType: ZoraCreatorRedeemMinterStrategy.TokenType.ERC1155
        });
        ZoraCreatorRedeemMinterStrategy.RedeemInstruction[] memory instructions = new ZoraCreatorRedeemMinterStrategy.RedeemInstruction[](1);
        instructions[0] = ZoraCreatorRedeemMinterStrategy.RedeemInstruction({
            tokenType: ZoraCreatorRedeemMinterStrategy.TokenType.ERC721,
            amount: 2,
            tokenIdStart: 0,
            tokenIdEnd: 1,
            tokenContract: address(burnToken),
            transferRecipient: address(0),
            burnFunction: bytes4(keccak256(bytes("burn(uint256)")))
        });
        ZoraCreatorRedeemMinterStrategy.RedeemInstructions memory redeemInstructions = ZoraCreatorRedeemMinterStrategy.RedeemInstructions({
            mintToken: mintToken,
            instructions: instructions,
            saleStart: 0,
            saleEnd: type(uint64).max,
            ethAmount: 1 ether,
            ethRecipient: address(0)
        });

        target.callSale(newTokenId, redeemMinter, abi.encodeWithSelector(ZoraCreatorRedeemMinterStrategy.setRedeem.selector, newTokenId, redeemInstructions));
        bytes32[] memory hashes = new bytes32[](1);
        hashes[0] = keccak256(abi.encode(redeemInstructions));
        vm.expectEmit(true, false, false, true);
        emit RedeemsCleared(address(target), hashes);
        target.callSale(newTokenId, redeemMinter, abi.encodeWithSelector(ZoraCreatorRedeemMinterStrategy.clearRedeem.selector, newTokenId, hashes));
        vm.stopPrank();

        vm.startPrank(tokenRecipient);
        burnToken.setApprovalForAll(address(redeemMinter), true);
        uint256[][] memory tokenIds = new uint256[][](1);
        tokenIds[0] = new uint256[](2);
        tokenIds[0][0] = 0;
        tokenIds[0][1] = 1;
        uint256[][] memory amounts = new uint256[][](1);
        vm.expectRevert(abi.encodeWithSignature("RedeemInstructionNotAllowed()"));
        target.mint{value: 1 ether}(redeemMinter, newTokenId, 10, rewardRecipients, abi.encode(redeemInstructions, tokenIds, amounts));
    }
}
