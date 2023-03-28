// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import {ERC20PresetMinterPauser} from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import {ERC721PresetMinterPauserAutoId} from "@openzeppelin/contracts/token/ERC721/presets/ERC721PresetMinterPauserAutoId.sol";
import {ERC1155PresetMinterPauser} from "@openzeppelin/contracts/token/ERC1155/presets/ERC1155PresetMinterPauser.sol";

import {ZoraCreator1155Impl} from "../../../src/nft/ZoraCreator1155Impl.sol";
import {Zora1155} from "../../../src/proxies/Zora1155.sol";
import {IZoraCreator1155} from "../../../src/interfaces/IZoraCreator1155.sol";
import {IRenderer1155} from "../../../src/interfaces/IRenderer1155.sol";
import {ICreatorRoyaltiesControl} from "../../../src/interfaces/ICreatorRoyaltiesControl.sol";
import {IZoraCreator1155Factory} from "../../../src/interfaces/IZoraCreator1155Factory.sol";
import {ZoraCreatorRedeemMinterStrategy} from "../../../src/minters/redeem/ZoraCreatorRedeemMinterStrategy.sol";

contract ZoraCreatorRedeemMinterStrategyTest is Test {
    ZoraCreator1155Impl internal target;
    ZoraCreatorRedeemMinterStrategy internal redeemMinter;
    address payable internal admin = payable(address(0x999));
    uint256 internal newTokenId;

    event RedeemSet(address indexed target, bytes32 indexed redeemsInstructionsHash, ZoraCreatorRedeemMinterStrategy.RedeemInstructions data);

    function setUp() external {
        bytes[] memory emptyData = new bytes[](0);
        ZoraCreator1155Impl targetImpl = new ZoraCreator1155Impl(0, address(0), address(0));
        Zora1155 proxy = new Zora1155(address(targetImpl));
        target = ZoraCreator1155Impl(address(proxy));
        target.initialize("test", ICreatorRoyaltiesControl.RoyaltyConfiguration(0, 0, address(0)), admin, emptyData);
        redeemMinter = new ZoraCreatorRedeemMinterStrategy();
        redeemMinter.initialize(address(target));
        vm.startPrank(admin);
        newTokenId = target.setupNewToken("https://zora.co/testing/token.json", 10);
        target.addPermission(newTokenId, address(redeemMinter), target.PERMISSION_BIT_MINTER());
        vm.stopPrank();
    }

    function test_ContractName() external {
        assertEq(redeemMinter.contractName(), "Redeem Minter Sale Strategy");
    }

    function test_Version() external {
        assertEq(redeemMinter.contractVersion(), "0.0.1");
    }

    // TODO: test events emitted
    function test_PurchaseFlowERC20() external {
        vm.startPrank(admin);

        address tokenRecipient = address(322);
        vm.deal(tokenRecipient, 20 ether);

        ERC20PresetMinterPauser randomToken = new ERC20PresetMinterPauser("Random Token", "RAND");
        randomToken.mint(address(tokenRecipient), 1000);

        ZoraCreatorRedeemMinterStrategy.RedeemToken memory redeemToken = ZoraCreatorRedeemMinterStrategy.RedeemToken({
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
            tokenContract: address(randomToken),
            transferRecipient: address(0),
            burnFunction: bytes4(keccak256(bytes("burnFrom(address,uint256)")))
        });
        ZoraCreatorRedeemMinterStrategy.RedeemInstructions memory redeemInstructions = ZoraCreatorRedeemMinterStrategy.RedeemInstructions({
            redeemToken: redeemToken,
            instructions: instructions,
            saleStart: 0,
            saleEnd: type(uint64).max,
            ethAmount: 1 ether,
            ethRecipient: address(0)
        });

        target.callSale(newTokenId, redeemMinter, abi.encodeWithSelector(ZoraCreatorRedeemMinterStrategy.setRedeem.selector, redeemInstructions));
        vm.stopPrank();

        vm.startPrank(tokenRecipient);
        uint256[] memory emptyArray = new uint256[](0);
        randomToken.approve(address(redeemMinter), 500);
        uint256[][] memory tokenIds = new uint256[][](1);
        tokenIds[0] = new uint256[](0);
        uint256[][] memory amounts = new uint256[][](1);
        amounts[0] = new uint256[](1);
        amounts[0][0] = 500;
        target.mint{value: 1 ether}(redeemMinter, newTokenId, 1, abi.encode(tokenRecipient, redeemInstructions, tokenIds, amounts));
        assertEq(address(target).balance, 1 ether);
        assertEq(target.balanceOf(tokenRecipient, newTokenId), 1);
        assertEq(randomToken.balanceOf(tokenRecipient), 500);
        vm.stopPrank();
    }
    /*
    function test_PurchaseFlowERC1155() external {
        vm.startPrank(admin);

        address tokenRecipient = address(322);
        vm.deal(tokenRecipient, 20 ether);

        ERC1155PresetMinterPauser redeemToken = new ERC1155PresetMinterPauser("https://zora.co/testing/token.json");
        redeemToken.mint(address(tokenRecipient), 1, 1000, "");

        vm.expectEmit(false, false, false, false);
        emit SaleSet(
            newTokenId,
            ZoraCreatorRedeemMinterStrategy.BurnToken({token: address(redeemToken), tokenId: 1}),
            ZoraCreatorRedeemMinterStrategy.BurnToRedeemSettings({
                ethAmountPerRedeem: 1 ether,
                burnAmountPerRedeem: 500,
                burnToRedeemStart: 0,
                burnToRedeemEnd: type(uint64).max,
                ethRecipient: address(0),
                burnFunctionSelector: bytes4(keccak256(bytes("burnBatch(address,uint256[],uint256[])")))
            })
        );
        target.callSale(
            newTokenId,
            redeemMinter,
            abi.encodeWithSelector(
                ZoraCreatorRedeemMinterStrategy.setBurnToRedeemForToken.selector,
                newTokenId,
                ZoraCreatorRedeemMinterStrategy.BurnToken({token: address(redeemToken), tokenId: 1}),
                ZoraCreatorRedeemMinterStrategy.BurnToRedeemSettings({
                    ethAmountPerRedeem: 1 ether,
                    burnAmountPerRedeem: 500,
                    burnToRedeemStart: 0,
                    burnToRedeemEnd: type(uint64).max,
                    ethRecipient: address(0),
                    burnFunctionSelector: bytes4(keccak256(bytes("burnBatch(address,uint256[],uint256[])")))
                }),
                ZoraCreatorRedeemMinterStrategy.BurnTokenType.ERC1155
            )
        );
        vm.stopPrank();

        vm.startPrank(tokenRecipient);
        redeemToken.setApprovalForAll(address(redeemMinter), true);
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 1;
        target.mint{value: 2 ether}(redeemMinter, newTokenId, 2, abi.encode(tokenRecipient, address(redeemToken), tokenIds));
        assertEq(address(target).balance, 2 ether);
        assertEq(target.balanceOf(tokenRecipient, newTokenId), 2);
        vm.stopPrank();
    }

    function test_PurchaseFlowERC721() external {
        vm.startPrank(admin);

        address tokenRecipient = address(322);
        vm.deal(tokenRecipient, 20 ether);

        ERC721PresetMinterPauserAutoId redeemToken = new ERC721PresetMinterPauserAutoId("Test token", "TEST", "https://zora.co/testing/token.json");
        redeemToken.mint(address(tokenRecipient));
        redeemToken.mint(address(tokenRecipient));

        vm.expectEmit(false, false, false, false);
        emit SaleSet(
            newTokenId,
            ZoraCreatorRedeemMinterStrategy.BurnToken({token: address(redeemToken), tokenId: 0}),
            ZoraCreatorRedeemMinterStrategy.BurnToRedeemSettings({
                ethAmountPerRedeem: 1 ether,
                burnAmountPerRedeem: 1,
                burnToRedeemStart: 0,
                burnToRedeemEnd: type(uint64).max,
                ethRecipient: address(0),
                burnFunctionSelector: bytes4(keccak256(bytes("burn(uint256)")))
            })
        );
        target.callSale(
            newTokenId,
            redeemMinter,
            abi.encodeWithSelector(
                ZoraCreatorRedeemMinterStrategy.setBurnToRedeemForToken.selector,
                newTokenId,
                ZoraCreatorRedeemMinterStrategy.BurnToken({token: address(redeemToken), tokenId: 0}),
                ZoraCreatorRedeemMinterStrategy.BurnToRedeemSettings({
                    ethAmountPerRedeem: 1 ether,
                    burnAmountPerRedeem: 1,
                    burnToRedeemStart: 0,
                    burnToRedeemEnd: type(uint64).max,
                    ethRecipient: address(0),
                    burnFunctionSelector: bytes4(keccak256(bytes("burn(uint256)")))
                }),
                ZoraCreatorRedeemMinterStrategy.BurnTokenType.ERC721
            )
        );
        vm.stopPrank();

        vm.startPrank(tokenRecipient);
        redeemToken.setApprovalForAll(address(redeemMinter), true);
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 0;
        tokenIds[1] = 1;
        target.mint{value: 2 ether}(redeemMinter, newTokenId, 2, abi.encode(tokenRecipient, address(redeemToken), tokenIds));
        assertEq(address(target).balance, 2 ether);
        assertEq(target.balanceOf(tokenRecipient, newTokenId), 2);
        vm.stopPrank();
    }

    function test_RedeemStart() external {
        vm.startPrank(admin);

        address tokenRecipient = address(322);
        vm.deal(tokenRecipient, 20 ether);

        ERC20PresetMinterPauser redeemToken = new ERC20PresetMinterPauser("Redeem Token", "RED");
        redeemToken.mint(address(tokenRecipient), 1000);

        target.callSale(
            newTokenId,
            redeemMinter,
            abi.encodeWithSelector(
                ZoraCreatorRedeemMinterStrategy.setBurnToRedeemForToken.selector,
                newTokenId,
                ZoraCreatorRedeemMinterStrategy.BurnToken({token: address(redeemToken), tokenId: 0}),
                ZoraCreatorRedeemMinterStrategy.BurnToRedeemSettings({
                    ethAmountPerRedeem: 1 ether,
                    burnAmountPerRedeem: 500,
                    burnToRedeemStart: uint64(block.timestamp + 1 days),
                    burnToRedeemEnd: type(uint64).max,
                    ethRecipient: address(0),
                    burnFunctionSelector: bytes4(keccak256(bytes("burnFrom(address,uint256)")))
                }),
                ZoraCreatorRedeemMinterStrategy.BurnTokenType.ERC20
            )
        );
        vm.stopPrank();

        vm.startPrank(tokenRecipient);
        redeemToken.approve(address(redeemMinter), 1000);
        uint256[] memory tokenIds = new uint256[](0);
        vm.expectRevert(abi.encodeWithSignature("SaleHasNotStarted()"));
        target.mint{value: 2 ether}(redeemMinter, newTokenId, 2, abi.encode(tokenRecipient, address(redeemToken), tokenIds));
        vm.stopPrank();
    }

    function test_RedeemEnd() external {
        vm.startPrank(admin);

        address tokenRecipient = address(322);
        vm.deal(tokenRecipient, 20 ether);

        ERC20PresetMinterPauser redeemToken = new ERC20PresetMinterPauser("Redeem Token", "RED");
        redeemToken.mint(address(tokenRecipient), 1000);

        target.callSale(
            newTokenId,
            redeemMinter,
            abi.encodeWithSelector(
                ZoraCreatorRedeemMinterStrategy.setBurnToRedeemForToken.selector,
                newTokenId,
                ZoraCreatorRedeemMinterStrategy.BurnToken({token: address(redeemToken), tokenId: 0}),
                ZoraCreatorRedeemMinterStrategy.BurnToRedeemSettings({
                    ethAmountPerRedeem: 1 ether,
                    burnAmountPerRedeem: 500,
                    burnToRedeemStart: 0,
                    burnToRedeemEnd: uint64(1 days),
                    ethRecipient: address(0),
                    burnFunctionSelector: bytes4(keccak256(bytes("burnFrom(address,uint256)")))
                }),
                ZoraCreatorRedeemMinterStrategy.BurnTokenType.ERC20
            )
        );
        vm.stopPrank();

        vm.warp(2 days);

        vm.startPrank(tokenRecipient);
        redeemToken.approve(address(redeemMinter), 1000);
        uint256[] memory tokenIds = new uint256[](0);
        vm.expectRevert(abi.encodeWithSignature("SaleEnded()"));
        target.mint{value: 2 ether}(redeemMinter, newTokenId, 2, abi.encode(tokenRecipient, address(redeemToken), tokenIds));
        vm.stopPrank();
    }

    function test_PricePerToken() external {
        vm.startPrank(admin);

        address tokenRecipient = address(322);
        vm.deal(tokenRecipient, 20 ether);

        ERC20PresetMinterPauser redeemToken = new ERC20PresetMinterPauser("Redeem Token", "RED");
        redeemToken.mint(address(tokenRecipient), 1000);

        target.callSale(
            newTokenId,
            redeemMinter,
            abi.encodeWithSelector(
                ZoraCreatorRedeemMinterStrategy.setBurnToRedeemForToken.selector,
                newTokenId,
                ZoraCreatorRedeemMinterStrategy.BurnToken({token: address(redeemToken), tokenId: 0}),
                ZoraCreatorRedeemMinterStrategy.BurnToRedeemSettings({
                    ethAmountPerRedeem: 1 ether,
                    burnAmountPerRedeem: 500,
                    burnToRedeemStart: 0,
                    burnToRedeemEnd: type(uint64).max,
                    ethRecipient: address(0),
                    burnFunctionSelector: bytes4(keccak256(bytes("burnFrom(address,uint256)")))
                }),
                ZoraCreatorRedeemMinterStrategy.BurnTokenType.ERC20
            )
        );
        vm.stopPrank();

        vm.startPrank(tokenRecipient);
        redeemToken.approve(address(redeemMinter), 1000);
        uint256[] memory tokenIds = new uint256[](0);
        vm.expectRevert(abi.encodeWithSignature("WrongValueSent()"));
        target.mint{value: 1.9 ether}(redeemMinter, newTokenId, 2, abi.encode(tokenRecipient, address(redeemToken), tokenIds));
        vm.expectRevert(abi.encodeWithSignature("WrongValueSent()"));
        target.mint{value: 2.1 ether}(redeemMinter, newTokenId, 2, abi.encode(tokenRecipient, address(redeemToken), tokenIds));
        target.mint{value: 2 ether}(redeemMinter, newTokenId, 2, abi.encode(tokenRecipient, address(redeemToken), tokenIds));
        assertEq(address(target).balance, 2 ether);
        assertEq(target.balanceOf(tokenRecipient, newTokenId), 2);
        vm.stopPrank();
    }

    function test_FundsRecipient() external {
        vm.startPrank(admin);

        address tokenRecipient = address(322);
        vm.deal(tokenRecipient, 20 ether);

        ERC20PresetMinterPauser redeemToken = new ERC20PresetMinterPauser("Redeem Token", "RED");
        redeemToken.mint(address(tokenRecipient), 1000);

        target.callSale(
            newTokenId,
            redeemMinter,
            abi.encodeWithSelector(
                ZoraCreatorRedeemMinterStrategy.setBurnToRedeemForToken.selector,
                newTokenId,
                ZoraCreatorRedeemMinterStrategy.BurnToken({token: address(redeemToken), tokenId: 0}),
                ZoraCreatorRedeemMinterStrategy.BurnToRedeemSettings({
                    ethAmountPerRedeem: 1 ether,
                    burnAmountPerRedeem: 500,
                    burnToRedeemStart: 0,
                    burnToRedeemEnd: type(uint64).max,
                    ethRecipient: address(0x1),
                    burnFunctionSelector: bytes4(keccak256(bytes("burnFrom(address,uint256)")))
                }),
                ZoraCreatorRedeemMinterStrategy.BurnTokenType.ERC20
            )
        );
        vm.stopPrank();

        vm.startPrank(tokenRecipient);
        redeemToken.approve(address(redeemMinter), 1000);
        uint256[] memory tokenIds = new uint256[](0);
        target.mint{value: 2 ether}(redeemMinter, newTokenId, 2, abi.encode(tokenRecipient, address(redeemToken), tokenIds));
        assertEq(address(0x1).balance, 2 ether);
        assertEq(target.balanceOf(tokenRecipient, newTokenId), 2);
        vm.stopPrank();
    }

    function test_ResetSale() external {
        vm.startPrank(admin);

        address tokenRecipient = address(322);
        vm.deal(tokenRecipient, 20 ether);

        ERC1155PresetMinterPauser redeemToken = new ERC1155PresetMinterPauser("https://zora.co/testing/token.json");
        redeemToken.mint(address(tokenRecipient), 1, 1000, "");
        redeemToken.mint(address(tokenRecipient), 2, 1000, "");

        target.callSale(
            newTokenId,
            redeemMinter,
            abi.encodeWithSelector(
                ZoraCreatorRedeemMinterStrategy.setBurnToRedeemForToken.selector,
                newTokenId,
                ZoraCreatorRedeemMinterStrategy.BurnToken({token: address(redeemToken), tokenId: 1}),
                ZoraCreatorRedeemMinterStrategy.BurnToRedeemSettings({
                    ethAmountPerRedeem: 1 ether,
                    burnAmountPerRedeem: 500,
                    burnToRedeemStart: 0,
                    burnToRedeemEnd: type(uint64).max,
                    ethRecipient: address(0),
                    burnFunctionSelector: bytes4(keccak256(bytes("burnBatch(address,uint256[],uint256[])")))
                }),
                ZoraCreatorRedeemMinterStrategy.BurnTokenType.ERC1155
            )
        );
        target.callSale(
            newTokenId,
            redeemMinter,
            abi.encodeWithSelector(
                ZoraCreatorRedeemMinterStrategy.setBurnToRedeemForToken.selector,
                newTokenId,
                ZoraCreatorRedeemMinterStrategy.BurnToken({token: address(redeemToken), tokenId: 2}),
                ZoraCreatorRedeemMinterStrategy.BurnToRedeemSettings({
                    ethAmountPerRedeem: 1 ether,
                    burnAmountPerRedeem: 500,
                    burnToRedeemStart: 0,
                    burnToRedeemEnd: type(uint64).max,
                    ethRecipient: address(0),
                    burnFunctionSelector: bytes4(keccak256(bytes("burnBatch(address,uint256[],uint256[])")))
                }),
                ZoraCreatorRedeemMinterStrategy.BurnTokenType.ERC1155
            )
        );

        target.callSale(newTokenId, redeemMinter, abi.encodeWithSelector(ZoraCreatorRedeemMinterStrategy.resetSale.selector, newTokenId));

        vm.stopPrank();

        ZoraCreatorRedeemMinterStrategy.BurnToRedeemSettings memory redeemSettings = redeemMinter.sale(newTokenId, address(redeemToken), 0);
        assertEq(redeemSettings.ethAmountPerRedeem, 0);
        assertEq(redeemSettings.burnAmountPerRedeem, 0);
        assertEq(redeemSettings.burnToRedeemStart, 0);
        assertEq(redeemSettings.burnToRedeemEnd, 0);
        assertEq(redeemSettings.ethRecipient, address(0));
        assertEq(redeemSettings.burnFunctionSelector, bytes4(0));

        vm.startPrank(tokenRecipient);
        redeemToken.setApprovalForAll(address(redeemMinter), true);
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 1;
        vm.expectRevert(abi.encodeWithSignature("NoSaleSet()"));
        target.mint{value: 2 ether}(redeemMinter, newTokenId, 2, abi.encode(tokenRecipient, address(redeemToken), tokenIds));
        tokenIds[0] = 2;
        vm.expectRevert(abi.encodeWithSignature("NoSaleSet()"));
        target.mint{value: 2 ether}(redeemMinter, newTokenId, 2, abi.encode(tokenRecipient, address(redeemToken), tokenIds));
        vm.stopPrank();
    }
    */
}
