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
import {ZoraCreatorBurnToRedeemMinterStrategy} from "../../../src/minters/token-redemption/ZoraCreatorBurnToRedeemMinterStrategy.sol";

contract ZoraCreatorBurnToRedeemMinterStrategyTest is Test {
    ZoraCreator1155Impl internal target;
    ZoraCreatorBurnToRedeemMinterStrategy internal burnToRedeemMinter;
    address internal admin = address(0x999);

    event SaleSet(
        uint256 tokenId,
        ZoraCreatorBurnToRedeemMinterStrategy.BurnToken burnToken,
        ZoraCreatorBurnToRedeemMinterStrategy.BurnToRedeemSettings burnToRedeemSettings
    );

    function setUp() external {
        bytes[] memory emptyData = new bytes[](0);
        ZoraCreator1155Impl targetImpl = new ZoraCreator1155Impl(0, address(0));
        Zora1155 proxy = new Zora1155(address(targetImpl));
        target = ZoraCreator1155Impl(address(proxy));
        target.initialize("test", ICreatorRoyaltiesControl.RoyaltyConfiguration(0, 0, address(0)), admin, emptyData);
        burnToRedeemMinter = new ZoraCreatorBurnToRedeemMinterStrategy(address(target));
    }

    function test_ContractName() external {
        assertEq(burnToRedeemMinter.contractName(), "Burn To Redeem Sale Strategy");
    }

    function test_Version() external {
        assertEq(burnToRedeemMinter.contractVersion(), "0.0.1");
    }

    function test_PurchaseFlowERC20() external {
        vm.startPrank(admin);
        uint256 newTokenId = target.setupNewToken("https://zora.co/testing/token.json", 10);
        target.addPermission(newTokenId, address(burnToRedeemMinter), target.PERMISSION_BIT_MINTER());

        address tokenRecipient = address(322);
        vm.deal(tokenRecipient, 20 ether);

        ERC20PresetMinterPauser redemptionToken = new ERC20PresetMinterPauser("Redemption Token", "RED");
        redemptionToken.mint(address(tokenRecipient), 1000);

        vm.expectEmit(false, false, false, false);
        emit SaleSet(
            newTokenId,
            ZoraCreatorBurnToRedeemMinterStrategy.BurnToken({token: address(redemptionToken), tokenId: 0}),
            ZoraCreatorBurnToRedeemMinterStrategy.BurnToRedeemSettings({
                ethAmountPerRedeem: 1 ether,
                burnAmountPerRedeem: 500,
                burnToRedeemStart: 0,
                burnToRedeemEnd: type(uint64).max,
                ethRecipient: address(0),
                burnFunctionSelector: bytes4(keccak256(bytes("burnFrom(address,uint256)")))
            })
        );
        target.callSale(
            newTokenId,
            burnToRedeemMinter,
            abi.encodeWithSelector(
                ZoraCreatorBurnToRedeemMinterStrategy.setBurnToRedeemForToken.selector,
                newTokenId,
                ZoraCreatorBurnToRedeemMinterStrategy.BurnToken({token: address(redemptionToken), tokenId: 0}),
                ZoraCreatorBurnToRedeemMinterStrategy.BurnToRedeemSettings({
                    ethAmountPerRedeem: 1 ether,
                    burnAmountPerRedeem: 500,
                    burnToRedeemStart: 0,
                    burnToRedeemEnd: type(uint64).max,
                    ethRecipient: address(0),
                    burnFunctionSelector: bytes4(keccak256(bytes("burnFrom(address,uint256)")))
                }),
                ZoraCreatorBurnToRedeemMinterStrategy.BurnTokenType.ERC20
            )
        );
        vm.stopPrank();

        vm.startPrank(tokenRecipient);
        redemptionToken.approve(address(burnToRedeemMinter), 1000);
        uint256[] memory tokenIds = new uint256[](0);
        target.mint{value: 2 ether}(burnToRedeemMinter, newTokenId, 2, abi.encode(tokenRecipient, address(redemptionToken), tokenIds));
        assertEq(address(target).balance, 2 ether);
        assertEq(target.balanceOf(tokenRecipient, newTokenId), 2);
        vm.stopPrank();
    }

    function test_PurchaseFlowERC1155() external {
        vm.startPrank(admin);
        uint256 newTokenId = target.setupNewToken("https://zora.co/testing/token.json", 10);
        target.addPermission(newTokenId, address(burnToRedeemMinter), target.PERMISSION_BIT_MINTER());

        address tokenRecipient = address(322);
        vm.deal(tokenRecipient, 20 ether);

        ERC1155PresetMinterPauser redemptionToken = new ERC1155PresetMinterPauser("https://zora.co/testing/token.json");
        redemptionToken.mint(address(tokenRecipient), 1, 1000, "");

        vm.expectEmit(false, false, false, false);
        emit SaleSet(
            newTokenId,
            ZoraCreatorBurnToRedeemMinterStrategy.BurnToken({token: address(redemptionToken), tokenId: 1}),
            ZoraCreatorBurnToRedeemMinterStrategy.BurnToRedeemSettings({
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
            burnToRedeemMinter,
            abi.encodeWithSelector(
                ZoraCreatorBurnToRedeemMinterStrategy.setBurnToRedeemForToken.selector,
                newTokenId,
                ZoraCreatorBurnToRedeemMinterStrategy.BurnToken({token: address(redemptionToken), tokenId: 1}),
                ZoraCreatorBurnToRedeemMinterStrategy.BurnToRedeemSettings({
                    ethAmountPerRedeem: 1 ether,
                    burnAmountPerRedeem: 500,
                    burnToRedeemStart: 0,
                    burnToRedeemEnd: type(uint64).max,
                    ethRecipient: address(0),
                    burnFunctionSelector: bytes4(keccak256(bytes("burnBatch(address,uint256[],uint256[])")))
                }),
                ZoraCreatorBurnToRedeemMinterStrategy.BurnTokenType.ERC1155
            )
        );
        vm.stopPrank();

        vm.startPrank(tokenRecipient);
        redemptionToken.setApprovalForAll(address(burnToRedeemMinter), true);
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 1;
        target.mint{value: 2 ether}(burnToRedeemMinter, newTokenId, 2, abi.encode(tokenRecipient, address(redemptionToken), tokenIds));
        assertEq(address(target).balance, 2 ether);
        assertEq(target.balanceOf(tokenRecipient, newTokenId), 2);
        vm.stopPrank();
    }

    function test_PurchaseFlowERC721() external {
        vm.startPrank(admin);
        uint256 newTokenId = target.setupNewToken("https://zora.co/testing/token.json", 10);
        target.addPermission(newTokenId, address(burnToRedeemMinter), target.PERMISSION_BIT_MINTER());

        address tokenRecipient = address(322);
        vm.deal(tokenRecipient, 20 ether);

        ERC721PresetMinterPauserAutoId redemptionToken = new ERC721PresetMinterPauserAutoId("Test token", "TEST", "https://zora.co/testing/token.json");
        redemptionToken.mint(address(tokenRecipient));
        redemptionToken.mint(address(tokenRecipient));

        vm.expectEmit(false, false, false, false);
        emit SaleSet(
            newTokenId,
            ZoraCreatorBurnToRedeemMinterStrategy.BurnToken({token: address(redemptionToken), tokenId: 0}),
            ZoraCreatorBurnToRedeemMinterStrategy.BurnToRedeemSettings({
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
            burnToRedeemMinter,
            abi.encodeWithSelector(
                ZoraCreatorBurnToRedeemMinterStrategy.setBurnToRedeemForToken.selector,
                newTokenId,
                ZoraCreatorBurnToRedeemMinterStrategy.BurnToken({token: address(redemptionToken), tokenId: 0}),
                ZoraCreatorBurnToRedeemMinterStrategy.BurnToRedeemSettings({
                    ethAmountPerRedeem: 1 ether,
                    burnAmountPerRedeem: 1,
                    burnToRedeemStart: 0,
                    burnToRedeemEnd: type(uint64).max,
                    ethRecipient: address(0),
                    burnFunctionSelector: bytes4(keccak256(bytes("burn(uint256)")))
                }),
                ZoraCreatorBurnToRedeemMinterStrategy.BurnTokenType.ERC721
            )
        );
        vm.stopPrank();

        vm.startPrank(tokenRecipient);
        redemptionToken.setApprovalForAll(address(burnToRedeemMinter), true);
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 0;
        tokenIds[1] = 1;
        target.mint{value: 2 ether}(burnToRedeemMinter, newTokenId, 2, abi.encode(tokenRecipient, address(redemptionToken), tokenIds));
        assertEq(address(target).balance, 2 ether);
        assertEq(target.balanceOf(tokenRecipient, newTokenId), 2);
        vm.stopPrank();
    }

    function test_RedemptionStart() external {
        vm.startPrank(admin);
        uint256 newTokenId = target.setupNewToken("https://zora.co/testing/token.json", 10);
        target.addPermission(newTokenId, address(burnToRedeemMinter), target.PERMISSION_BIT_MINTER());

        address tokenRecipient = address(322);
        vm.deal(tokenRecipient, 20 ether);

        ERC20PresetMinterPauser redemptionToken = new ERC20PresetMinterPauser("Redemption Token", "RED");
        redemptionToken.mint(address(tokenRecipient), 1000);

        target.callSale(
            newTokenId,
            burnToRedeemMinter,
            abi.encodeWithSelector(
                ZoraCreatorBurnToRedeemMinterStrategy.setBurnToRedeemForToken.selector,
                newTokenId,
                ZoraCreatorBurnToRedeemMinterStrategy.BurnToken({token: address(redemptionToken), tokenId: 0}),
                ZoraCreatorBurnToRedeemMinterStrategy.BurnToRedeemSettings({
                    ethAmountPerRedeem: 1 ether,
                    burnAmountPerRedeem: 500,
                    burnToRedeemStart: uint64(block.timestamp + 1 days),
                    burnToRedeemEnd: type(uint64).max,
                    ethRecipient: address(0),
                    burnFunctionSelector: bytes4(keccak256(bytes("burnFrom(address,uint256)")))
                }),
                ZoraCreatorBurnToRedeemMinterStrategy.BurnTokenType.ERC20
            )
        );
        vm.stopPrank();

        vm.startPrank(tokenRecipient);
        redemptionToken.approve(address(burnToRedeemMinter), 1000);
        uint256[] memory tokenIds = new uint256[](0);
        vm.expectRevert(abi.encodeWithSignature("SaleHasNotStarted()"));
        target.mint{value: 2 ether}(burnToRedeemMinter, newTokenId, 2, abi.encode(tokenRecipient, address(redemptionToken), tokenIds));
        vm.stopPrank();
    }

    function test_RedemptionEnd() external {
        vm.startPrank(admin);
        uint256 newTokenId = target.setupNewToken("https://zora.co/testing/token.json", 10);
        target.addPermission(newTokenId, address(burnToRedeemMinter), target.PERMISSION_BIT_MINTER());

        address tokenRecipient = address(322);
        vm.deal(tokenRecipient, 20 ether);

        ERC20PresetMinterPauser redemptionToken = new ERC20PresetMinterPauser("Redemption Token", "RED");
        redemptionToken.mint(address(tokenRecipient), 1000);

        target.callSale(
            newTokenId,
            burnToRedeemMinter,
            abi.encodeWithSelector(
                ZoraCreatorBurnToRedeemMinterStrategy.setBurnToRedeemForToken.selector,
                newTokenId,
                ZoraCreatorBurnToRedeemMinterStrategy.BurnToken({token: address(redemptionToken), tokenId: 0}),
                ZoraCreatorBurnToRedeemMinterStrategy.BurnToRedeemSettings({
                    ethAmountPerRedeem: 1 ether,
                    burnAmountPerRedeem: 500,
                    burnToRedeemStart: 0,
                    burnToRedeemEnd: uint64(1 days),
                    ethRecipient: address(0),
                    burnFunctionSelector: bytes4(keccak256(bytes("burnFrom(address,uint256)")))
                }),
                ZoraCreatorBurnToRedeemMinterStrategy.BurnTokenType.ERC20
            )
        );
        vm.stopPrank();

        vm.warp(2 days);

        vm.startPrank(tokenRecipient);
        redemptionToken.approve(address(burnToRedeemMinter), 1000);
        uint256[] memory tokenIds = new uint256[](0);
        vm.expectRevert(abi.encodeWithSignature("SaleEnded()"));
        target.mint{value: 2 ether}(burnToRedeemMinter, newTokenId, 2, abi.encode(tokenRecipient, address(redemptionToken), tokenIds));
        vm.stopPrank();
    }

    function test_PricePerToken() external {
        vm.startPrank(admin);
        uint256 newTokenId = target.setupNewToken("https://zora.co/testing/token.json", 10);
        target.addPermission(newTokenId, address(burnToRedeemMinter), target.PERMISSION_BIT_MINTER());

        address tokenRecipient = address(322);
        vm.deal(tokenRecipient, 20 ether);

        ERC20PresetMinterPauser redemptionToken = new ERC20PresetMinterPauser("Redemption Token", "RED");
        redemptionToken.mint(address(tokenRecipient), 1000);

        target.callSale(
            newTokenId,
            burnToRedeemMinter,
            abi.encodeWithSelector(
                ZoraCreatorBurnToRedeemMinterStrategy.setBurnToRedeemForToken.selector,
                newTokenId,
                ZoraCreatorBurnToRedeemMinterStrategy.BurnToken({token: address(redemptionToken), tokenId: 0}),
                ZoraCreatorBurnToRedeemMinterStrategy.BurnToRedeemSettings({
                    ethAmountPerRedeem: 1 ether,
                    burnAmountPerRedeem: 500,
                    burnToRedeemStart: 0,
                    burnToRedeemEnd: type(uint64).max,
                    ethRecipient: address(0),
                    burnFunctionSelector: bytes4(keccak256(bytes("burnFrom(address,uint256)")))
                }),
                ZoraCreatorBurnToRedeemMinterStrategy.BurnTokenType.ERC20
            )
        );
        vm.stopPrank();

        vm.startPrank(tokenRecipient);
        redemptionToken.approve(address(burnToRedeemMinter), 1000);
        uint256[] memory tokenIds = new uint256[](0);
        vm.expectRevert(abi.encodeWithSignature("WrongValueSent()"));
        target.mint{value: 1.9 ether}(burnToRedeemMinter, newTokenId, 2, abi.encode(tokenRecipient, address(redemptionToken), tokenIds));
        vm.expectRevert(abi.encodeWithSignature("WrongValueSent()"));
        target.mint{value: 2.1 ether}(burnToRedeemMinter, newTokenId, 2, abi.encode(tokenRecipient, address(redemptionToken), tokenIds));
        target.mint{value: 2 ether}(burnToRedeemMinter, newTokenId, 2, abi.encode(tokenRecipient, address(redemptionToken), tokenIds));
        assertEq(address(target).balance, 2 ether);
        assertEq(target.balanceOf(tokenRecipient, newTokenId), 2);
        vm.stopPrank();
    }

    function test_FundsRecipient() external {
        vm.startPrank(admin);
        uint256 newTokenId = target.setupNewToken("https://zora.co/testing/token.json", 10);
        target.addPermission(newTokenId, address(burnToRedeemMinter), target.PERMISSION_BIT_MINTER());

        address tokenRecipient = address(322);
        vm.deal(tokenRecipient, 20 ether);

        ERC20PresetMinterPauser redemptionToken = new ERC20PresetMinterPauser("Redemption Token", "RED");
        redemptionToken.mint(address(tokenRecipient), 1000);

        target.callSale(
            newTokenId,
            burnToRedeemMinter,
            abi.encodeWithSelector(
                ZoraCreatorBurnToRedeemMinterStrategy.setBurnToRedeemForToken.selector,
                newTokenId,
                ZoraCreatorBurnToRedeemMinterStrategy.BurnToken({token: address(redemptionToken), tokenId: 0}),
                ZoraCreatorBurnToRedeemMinterStrategy.BurnToRedeemSettings({
                    ethAmountPerRedeem: 1 ether,
                    burnAmountPerRedeem: 500,
                    burnToRedeemStart: 0,
                    burnToRedeemEnd: type(uint64).max,
                    ethRecipient: address(0x1),
                    burnFunctionSelector: bytes4(keccak256(bytes("burnFrom(address,uint256)")))
                }),
                ZoraCreatorBurnToRedeemMinterStrategy.BurnTokenType.ERC20
            )
        );
        vm.stopPrank();

        vm.startPrank(tokenRecipient);
        redemptionToken.approve(address(burnToRedeemMinter), 1000);
        uint256[] memory tokenIds = new uint256[](0);
        target.mint{value: 2 ether}(burnToRedeemMinter, newTokenId, 2, abi.encode(tokenRecipient, address(redemptionToken), tokenIds));
        assertEq(address(0x1).balance, 2 ether);
        assertEq(target.balanceOf(tokenRecipient, newTokenId), 2);
        vm.stopPrank();
    }

    function test_ResetSale() external {
        vm.startPrank(admin);
        uint256 newTokenId = target.setupNewToken("https://zora.co/testing/token.json", 10);
        target.addPermission(newTokenId, address(burnToRedeemMinter), target.PERMISSION_BIT_MINTER());

        address tokenRecipient = address(322);
        vm.deal(tokenRecipient, 20 ether);

        ERC1155PresetMinterPauser redemptionToken = new ERC1155PresetMinterPauser("https://zora.co/testing/token.json");
        redemptionToken.mint(address(tokenRecipient), 1, 1000, "");
        redemptionToken.mint(address(tokenRecipient), 2, 1000, "");

        target.callSale(
            newTokenId,
            burnToRedeemMinter,
            abi.encodeWithSelector(
                ZoraCreatorBurnToRedeemMinterStrategy.setBurnToRedeemForToken.selector,
                newTokenId,
                ZoraCreatorBurnToRedeemMinterStrategy.BurnToken({token: address(redemptionToken), tokenId: 1}),
                ZoraCreatorBurnToRedeemMinterStrategy.BurnToRedeemSettings({
                    ethAmountPerRedeem: 1 ether,
                    burnAmountPerRedeem: 500,
                    burnToRedeemStart: 0,
                    burnToRedeemEnd: type(uint64).max,
                    ethRecipient: address(0),
                    burnFunctionSelector: bytes4(keccak256(bytes("burnBatch(address,uint256[],uint256[])")))
                }),
                ZoraCreatorBurnToRedeemMinterStrategy.BurnTokenType.ERC1155
            )
        );
        target.callSale(
            newTokenId,
            burnToRedeemMinter,
            abi.encodeWithSelector(
                ZoraCreatorBurnToRedeemMinterStrategy.setBurnToRedeemForToken.selector,
                newTokenId,
                ZoraCreatorBurnToRedeemMinterStrategy.BurnToken({token: address(redemptionToken), tokenId: 2}),
                ZoraCreatorBurnToRedeemMinterStrategy.BurnToRedeemSettings({
                    ethAmountPerRedeem: 1 ether,
                    burnAmountPerRedeem: 500,
                    burnToRedeemStart: 0,
                    burnToRedeemEnd: type(uint64).max,
                    ethRecipient: address(0),
                    burnFunctionSelector: bytes4(keccak256(bytes("burnBatch(address,uint256[],uint256[])")))
                }),
                ZoraCreatorBurnToRedeemMinterStrategy.BurnTokenType.ERC1155
            )
        );

        target.callSale(newTokenId, burnToRedeemMinter, abi.encodeWithSelector(ZoraCreatorBurnToRedeemMinterStrategy.resetSale.selector, newTokenId));

        vm.stopPrank();

        ZoraCreatorBurnToRedeemMinterStrategy.BurnToRedeemSettings memory redemptionSettings = burnToRedeemMinter.sale(newTokenId, address(redemptionToken), 0);
        assertEq(redemptionSettings.ethAmountPerRedeem, 0);
        assertEq(redemptionSettings.burnAmountPerRedeem, 0);
        assertEq(redemptionSettings.burnToRedeemStart, 0);
        assertEq(redemptionSettings.burnToRedeemEnd, 0);
        assertEq(redemptionSettings.ethRecipient, address(0));
        assertEq(redemptionSettings.burnFunctionSelector, bytes4(0));

        vm.startPrank(tokenRecipient);
        redemptionToken.setApprovalForAll(address(burnToRedeemMinter), true);
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 1;
        vm.expectRevert(abi.encodeWithSignature("NoSaleSet()"));
        target.mint{value: 2 ether}(burnToRedeemMinter, newTokenId, 2, abi.encode(tokenRecipient, address(redemptionToken), tokenIds));
        tokenIds[0] = 2;
        vm.expectRevert(abi.encodeWithSignature("NoSaleSet()"));
        target.mint{value: 2 ether}(burnToRedeemMinter, newTokenId, 2, abi.encode(tokenRecipient, address(redemptionToken), tokenIds));
        vm.stopPrank();
    }
}
