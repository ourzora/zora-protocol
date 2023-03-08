// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import {ERC20PresetMinterPauser} from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import {ERC721PresetMinterPauserAutoId} from "@openzeppelin/contracts/token/ERC721/presets/ERC721PresetMinterPauserAutoId.sol";
import {ERC1155PresetMinterPauser} from "@openzeppelin/contracts/token/ERC1155/presets/ERC1155PresetMinterPauser.sol";

import {ZoraCreator1155Impl} from "../../../src/nft/ZoraCreator1155Impl.sol";
import {ZoraCreator1155Proxy} from "../../../src/proxies/ZoraCreator1155Proxy.sol";
import {IZoraCreator1155} from "../../../src/interfaces/IZoraCreator1155.sol";
import {IRenderer1155} from "../../../src/interfaces/IRenderer1155.sol";
import {ICreatorRoyaltiesControl} from "../../../src/interfaces/ICreatorRoyaltiesControl.sol";
import {IZoraCreator1155Factory} from "../../../src/interfaces/IZoraCreator1155Factory.sol";
import {ZoraCreatorTokenRedemptionMinterStrategy} from "../../../src/minters/token-redemption/ZoraCreatorTokenRedemptionMinterStrategy.sol";

contract ZoraCreatorTokenRedemptionMinterStrategyTest is Test {
    ZoraCreator1155Impl internal target;
    ZoraCreatorTokenRedemptionMinterStrategy internal redemptionMinter;
    address internal admin = address(0x999);

    event SaleSet(
        uint256 tokenId,
        ZoraCreatorTokenRedemptionMinterStrategy.RedemptionToken redemptionToken,
        ZoraCreatorTokenRedemptionMinterStrategy.RedemptionSettings redemptionSettings
    );

    function setUp() external {
        bytes[] memory emptyData = new bytes[](0);
        ZoraCreator1155Impl targetImpl = new ZoraCreator1155Impl(0, address(0));
        ZoraCreator1155Proxy proxy = new ZoraCreator1155Proxy(address(targetImpl));
        target = ZoraCreator1155Impl(address(proxy));
        target.initialize("test", ICreatorRoyaltiesControl.RoyaltyConfiguration(0, address(0)), admin, emptyData);
        redemptionMinter = new ZoraCreatorTokenRedemptionMinterStrategy(address(target));
    }

    function test_ContractName() external {
        assertEq(redemptionMinter.contractName(), "Token Redemption Sale Strategy");
    }

    function test_Version() external {
        assertEq(redemptionMinter.contractVersion(), "0.0.1");
    }

    function test_PurchaseFlowERC20() external {
        vm.startPrank(admin);
        uint256 newTokenId = target.setupNewToken("https://zora.co/testing/token.json", 10);
        target.addPermission(newTokenId, address(redemptionMinter), target.PERMISSION_BIT_MINTER());

        address tokenRecipient = address(322);
        vm.deal(tokenRecipient, 20 ether);

        ERC20PresetMinterPauser redemptionToken = new ERC20PresetMinterPauser("Redemption Token", "RED");
        redemptionToken.mint(address(tokenRecipient), 1000);

        vm.expectEmit(false, false, false, false);
        emit SaleSet(
            newTokenId,
            ZoraCreatorTokenRedemptionMinterStrategy.RedemptionToken({token: address(redemptionToken), tokenId: 0}),
            ZoraCreatorTokenRedemptionMinterStrategy.RedemptionSettings({
                ethAmountPerMint: 1 ether,
                redemptionAmountPerMint: 500,
                redemptionStart: 0,
                redemptionEnd: type(uint64).max,
                redemptionRecipient: address(0xdead),
                fundsRecipient: address(0)
            })
        );
        target.callSale(
            newTokenId,
            redemptionMinter,
            abi.encodeWithSelector(
                ZoraCreatorTokenRedemptionMinterStrategy.setTokenRedemption.selector,
                newTokenId,
                ZoraCreatorTokenRedemptionMinterStrategy.RedemptionToken({token: address(redemptionToken), tokenId: 0}),
                ZoraCreatorTokenRedemptionMinterStrategy.RedemptionSettings({
                    ethAmountPerMint: 1 ether,
                    redemptionAmountPerMint: 500,
                    redemptionStart: 0,
                    redemptionEnd: type(uint64).max,
                    redemptionRecipient: address(0xdead),
                    fundsRecipient: address(0)
                }),
                ZoraCreatorTokenRedemptionMinterStrategy.RedemptionTokenType.ERC20
            )
        );
        vm.stopPrank();

        vm.startPrank(tokenRecipient);
        redemptionToken.approve(address(redemptionMinter), 1000);
        uint256[] memory tokenIds = new uint256[](0);
        target.purchase{value: 2 ether}(redemptionMinter, newTokenId, 2, abi.encode(tokenRecipient, address(redemptionToken), tokenIds));
        assertEq(address(target).balance, 2 ether);
        assertEq(target.balanceOf(tokenRecipient, newTokenId), 2);
        assertEq(redemptionToken.balanceOf(address(0xdead)), 1000);
        vm.stopPrank();
    }

    function test_PurchaseFlowERC1155() external {
        vm.startPrank(admin);
        uint256 newTokenId = target.setupNewToken("https://zora.co/testing/token.json", 10);
        target.addPermission(newTokenId, address(redemptionMinter), target.PERMISSION_BIT_MINTER());

        address tokenRecipient = address(322);
        vm.deal(tokenRecipient, 20 ether);

        ERC1155PresetMinterPauser redemptionToken = new ERC1155PresetMinterPauser("https://zora.co/testing/token.json");
        redemptionToken.mint(address(tokenRecipient), 1, 1000, "");

        vm.expectEmit(false, false, false, false);
        emit SaleSet(
            newTokenId,
            ZoraCreatorTokenRedemptionMinterStrategy.RedemptionToken({token: address(redemptionToken), tokenId: 1}),
            ZoraCreatorTokenRedemptionMinterStrategy.RedemptionSettings({
                ethAmountPerMint: 1 ether,
                redemptionAmountPerMint: 500,
                redemptionStart: 0,
                redemptionEnd: type(uint64).max,
                redemptionRecipient: address(0xdead),
                fundsRecipient: address(0)
            })
        );
        target.callSale(
            newTokenId,
            redemptionMinter,
            abi.encodeWithSelector(
                ZoraCreatorTokenRedemptionMinterStrategy.setTokenRedemption.selector,
                newTokenId,
                ZoraCreatorTokenRedemptionMinterStrategy.RedemptionToken({token: address(redemptionToken), tokenId: 1}),
                ZoraCreatorTokenRedemptionMinterStrategy.RedemptionSettings({
                    ethAmountPerMint: 1 ether,
                    redemptionAmountPerMint: 500,
                    redemptionStart: 0,
                    redemptionEnd: type(uint64).max,
                    redemptionRecipient: address(0xdead),
                    fundsRecipient: address(0)
                }),
                ZoraCreatorTokenRedemptionMinterStrategy.RedemptionTokenType.ERC1155
            )
        );
        vm.stopPrank();

        vm.startPrank(tokenRecipient);
        redemptionToken.setApprovalForAll(address(redemptionMinter), true);
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 1;
        target.purchase{value: 2 ether}(redemptionMinter, newTokenId, 2, abi.encode(tokenRecipient, address(redemptionToken), tokenIds));
        assertEq(address(target).balance, 2 ether);
        assertEq(target.balanceOf(tokenRecipient, newTokenId), 2);
        assertEq(redemptionToken.balanceOf(address(0xdead), 1), 1000);
        vm.stopPrank();
    }

    function test_PurchaseFlowERC721() external {
        vm.startPrank(admin);
        uint256 newTokenId = target.setupNewToken("https://zora.co/testing/token.json", 10);
        target.addPermission(newTokenId, address(redemptionMinter), target.PERMISSION_BIT_MINTER());

        address tokenRecipient = address(322);
        vm.deal(tokenRecipient, 20 ether);

        ERC721PresetMinterPauserAutoId redemptionToken = new ERC721PresetMinterPauserAutoId("Test token", "TEST", "https://zora.co/testing/token.json");
        redemptionToken.mint(address(tokenRecipient));
        redemptionToken.mint(address(tokenRecipient));

        vm.expectEmit(false, false, false, false);
        emit SaleSet(
            newTokenId,
            ZoraCreatorTokenRedemptionMinterStrategy.RedemptionToken({token: address(redemptionToken), tokenId: 0}),
            ZoraCreatorTokenRedemptionMinterStrategy.RedemptionSettings({
                ethAmountPerMint: 1 ether,
                redemptionAmountPerMint: 1,
                redemptionStart: 0,
                redemptionEnd: type(uint64).max,
                redemptionRecipient: address(0xdead),
                fundsRecipient: address(0)
            })
        );
        target.callSale(
            newTokenId,
            redemptionMinter,
            abi.encodeWithSelector(
                ZoraCreatorTokenRedemptionMinterStrategy.setTokenRedemption.selector,
                newTokenId,
                ZoraCreatorTokenRedemptionMinterStrategy.RedemptionToken({token: address(redemptionToken), tokenId: 0}),
                ZoraCreatorTokenRedemptionMinterStrategy.RedemptionSettings({
                    ethAmountPerMint: 1 ether,
                    redemptionAmountPerMint: 1,
                    redemptionStart: 0,
                    redemptionEnd: type(uint64).max,
                    redemptionRecipient: address(0xdead),
                    fundsRecipient: address(0)
                }),
                ZoraCreatorTokenRedemptionMinterStrategy.RedemptionTokenType.ERC721
            )
        );
        vm.stopPrank();

        vm.startPrank(tokenRecipient);
        redemptionToken.setApprovalForAll(address(redemptionMinter), true);
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 0;
        tokenIds[1] = 1;
        target.purchase{value: 2 ether}(redemptionMinter, newTokenId, 2, abi.encode(tokenRecipient, address(redemptionToken), tokenIds));
        assertEq(address(target).balance, 2 ether);
        assertEq(target.balanceOf(tokenRecipient, newTokenId), 2);
        assertEq(redemptionToken.balanceOf(address(0xdead)), 2);
        vm.stopPrank();
    }

    function test_RedemptionStart() external {
        vm.startPrank(admin);
        uint256 newTokenId = target.setupNewToken("https://zora.co/testing/token.json", 10);
        target.addPermission(newTokenId, address(redemptionMinter), target.PERMISSION_BIT_MINTER());

        address tokenRecipient = address(322);
        vm.deal(tokenRecipient, 20 ether);

        ERC20PresetMinterPauser redemptionToken = new ERC20PresetMinterPauser("Redemption Token", "RED");
        redemptionToken.mint(address(tokenRecipient), 1000);

        vm.expectEmit(false, false, false, false);
        emit SaleSet(
            newTokenId,
            ZoraCreatorTokenRedemptionMinterStrategy.RedemptionToken({token: address(redemptionToken), tokenId: 0}),
            ZoraCreatorTokenRedemptionMinterStrategy.RedemptionSettings({
                ethAmountPerMint: 1 ether,
                redemptionAmountPerMint: 500,
                redemptionStart: uint64(block.timestamp + 1 days),
                redemptionEnd: type(uint64).max,
                redemptionRecipient: address(0xdead),
                fundsRecipient: address(0)
            })
        );
        target.callSale(
            newTokenId,
            redemptionMinter,
            abi.encodeWithSelector(
                ZoraCreatorTokenRedemptionMinterStrategy.setTokenRedemption.selector,
                newTokenId,
                ZoraCreatorTokenRedemptionMinterStrategy.RedemptionToken({token: address(redemptionToken), tokenId: 0}),
                ZoraCreatorTokenRedemptionMinterStrategy.RedemptionSettings({
                    ethAmountPerMint: 1 ether,
                    redemptionAmountPerMint: 500,
                    redemptionStart: uint64(block.timestamp + 1 days),
                    redemptionEnd: type(uint64).max,
                    redemptionRecipient: address(0xdead),
                    fundsRecipient: address(0)
                }),
                ZoraCreatorTokenRedemptionMinterStrategy.RedemptionTokenType.ERC20
            )
        );
        vm.stopPrank();

        vm.startPrank(tokenRecipient);
        redemptionToken.approve(address(redemptionMinter), 1000);
        uint256[] memory tokenIds = new uint256[](0);
        vm.expectRevert(abi.encodeWithSignature("SaleHasNotStarted()"));
        target.purchase{value: 2 ether}(redemptionMinter, newTokenId, 2, abi.encode(tokenRecipient, address(redemptionToken), tokenIds));
        vm.stopPrank();
    }

    function test_RedemptionEnd() external {
        vm.startPrank(admin);
        uint256 newTokenId = target.setupNewToken("https://zora.co/testing/token.json", 10);
        target.addPermission(newTokenId, address(redemptionMinter), target.PERMISSION_BIT_MINTER());

        address tokenRecipient = address(322);
        vm.deal(tokenRecipient, 20 ether);

        ERC20PresetMinterPauser redemptionToken = new ERC20PresetMinterPauser("Redemption Token", "RED");
        redemptionToken.mint(address(tokenRecipient), 1000);

        vm.expectEmit(false, false, false, false);
        emit SaleSet(
            newTokenId,
            ZoraCreatorTokenRedemptionMinterStrategy.RedemptionToken({token: address(redemptionToken), tokenId: 0}),
            ZoraCreatorTokenRedemptionMinterStrategy.RedemptionSettings({
                ethAmountPerMint: 1 ether,
                redemptionAmountPerMint: 500,
                redemptionStart: 0,
                redemptionEnd: uint64(1 days),
                redemptionRecipient: address(0xdead),
                fundsRecipient: address(0)
            })
        );
        target.callSale(
            newTokenId,
            redemptionMinter,
            abi.encodeWithSelector(
                ZoraCreatorTokenRedemptionMinterStrategy.setTokenRedemption.selector,
                newTokenId,
                ZoraCreatorTokenRedemptionMinterStrategy.RedemptionToken({token: address(redemptionToken), tokenId: 0}),
                ZoraCreatorTokenRedemptionMinterStrategy.RedemptionSettings({
                    ethAmountPerMint: 1 ether,
                    redemptionAmountPerMint: 500,
                    redemptionStart: 0,
                    redemptionEnd: uint64(1 days),
                    redemptionRecipient: address(0xdead),
                    fundsRecipient: address(0)
                }),
                ZoraCreatorTokenRedemptionMinterStrategy.RedemptionTokenType.ERC20
            )
        );
        vm.stopPrank();

        vm.warp(2 days);

        vm.startPrank(tokenRecipient);
        redemptionToken.approve(address(redemptionMinter), 1000);
        uint256[] memory tokenIds = new uint256[](0);
        vm.expectRevert(abi.encodeWithSignature("SaleEnded()"));
        target.purchase{value: 2 ether}(redemptionMinter, newTokenId, 2, abi.encode(tokenRecipient, address(redemptionToken), tokenIds));
        vm.stopPrank();
    }

    function test_PricePerToken() external {
        vm.startPrank(admin);
        uint256 newTokenId = target.setupNewToken("https://zora.co/testing/token.json", 10);
        target.addPermission(newTokenId, address(redemptionMinter), target.PERMISSION_BIT_MINTER());

        address tokenRecipient = address(322);
        vm.deal(tokenRecipient, 20 ether);

        ERC20PresetMinterPauser redemptionToken = new ERC20PresetMinterPauser("Redemption Token", "RED");
        redemptionToken.mint(address(tokenRecipient), 1000);

        vm.expectEmit(false, false, false, false);
        emit SaleSet(
            newTokenId,
            ZoraCreatorTokenRedemptionMinterStrategy.RedemptionToken({token: address(redemptionToken), tokenId: 0}),
            ZoraCreatorTokenRedemptionMinterStrategy.RedemptionSettings({
                ethAmountPerMint: 1 ether,
                redemptionAmountPerMint: 500,
                redemptionStart: 0,
                redemptionEnd: type(uint64).max,
                redemptionRecipient: address(0xdead),
                fundsRecipient: address(0)
            })
        );
        target.callSale(
            newTokenId,
            redemptionMinter,
            abi.encodeWithSelector(
                ZoraCreatorTokenRedemptionMinterStrategy.setTokenRedemption.selector,
                newTokenId,
                ZoraCreatorTokenRedemptionMinterStrategy.RedemptionToken({token: address(redemptionToken), tokenId: 0}),
                ZoraCreatorTokenRedemptionMinterStrategy.RedemptionSettings({
                    ethAmountPerMint: 1 ether,
                    redemptionAmountPerMint: 500,
                    redemptionStart: 0,
                    redemptionEnd: type(uint64).max,
                    redemptionRecipient: address(0xdead),
                    fundsRecipient: address(0)
                }),
                ZoraCreatorTokenRedemptionMinterStrategy.RedemptionTokenType.ERC20
            )
        );
        vm.stopPrank();

        vm.startPrank(tokenRecipient);
        redemptionToken.approve(address(redemptionMinter), 1000);
        uint256[] memory tokenIds = new uint256[](0);
        vm.expectRevert(abi.encodeWithSignature("WrongValueSent()"));
        target.purchase{value: 1.9 ether}(redemptionMinter, newTokenId, 2, abi.encode(tokenRecipient, address(redemptionToken), tokenIds));
        vm.expectRevert(abi.encodeWithSignature("WrongValueSent()"));
        target.purchase{value: 2.1 ether}(redemptionMinter, newTokenId, 2, abi.encode(tokenRecipient, address(redemptionToken), tokenIds));
        target.purchase{value: 2 ether}(redemptionMinter, newTokenId, 2, abi.encode(tokenRecipient, address(redemptionToken), tokenIds));
        assertEq(address(target).balance, 2 ether);
        assertEq(target.balanceOf(tokenRecipient, newTokenId), 2);
        assertEq(redemptionToken.balanceOf(address(0xdead)), 1000);
        vm.stopPrank();
    }

    function test_FundsRecipient() external {
        vm.startPrank(admin);
        uint256 newTokenId = target.setupNewToken("https://zora.co/testing/token.json", 10);
        target.addPermission(newTokenId, address(redemptionMinter), target.PERMISSION_BIT_MINTER());

        address tokenRecipient = address(322);
        vm.deal(tokenRecipient, 20 ether);

        ERC20PresetMinterPauser redemptionToken = new ERC20PresetMinterPauser("Redemption Token", "RED");
        redemptionToken.mint(address(tokenRecipient), 1000);

        target.callSale(
            newTokenId,
            redemptionMinter,
            abi.encodeWithSelector(
                ZoraCreatorTokenRedemptionMinterStrategy.setTokenRedemption.selector,
                newTokenId,
                ZoraCreatorTokenRedemptionMinterStrategy.RedemptionToken({token: address(redemptionToken), tokenId: 0}),
                ZoraCreatorTokenRedemptionMinterStrategy.RedemptionSettings({
                    ethAmountPerMint: 1 ether,
                    redemptionAmountPerMint: 500,
                    redemptionStart: 0,
                    redemptionEnd: type(uint64).max,
                    redemptionRecipient: address(0xdead),
                    fundsRecipient: address(0x1)
                }),
                ZoraCreatorTokenRedemptionMinterStrategy.RedemptionTokenType.ERC20
            )
        );
        vm.stopPrank();

        vm.startPrank(tokenRecipient);
        redemptionToken.approve(address(redemptionMinter), 1000);
        uint256[] memory tokenIds = new uint256[](0);
        target.purchase{value: 2 ether}(redemptionMinter, newTokenId, 2, abi.encode(tokenRecipient, address(redemptionToken), tokenIds));
        assertEq(address(0x1).balance, 2 ether);
        assertEq(target.balanceOf(tokenRecipient, newTokenId), 2);
        assertEq(redemptionToken.balanceOf(address(0xdead)), 1000);
        vm.stopPrank();
    }

    function test_ResetSale() external {
        vm.startPrank(admin);
        uint256 newTokenId = target.setupNewToken("https://zora.co/testing/token.json", 10);
        target.addPermission(newTokenId, address(redemptionMinter), target.PERMISSION_BIT_MINTER());

        address tokenRecipient = address(322);
        vm.deal(tokenRecipient, 20 ether);

        ERC1155PresetMinterPauser redemptionToken = new ERC1155PresetMinterPauser("https://zora.co/testing/token.json");
        redemptionToken.mint(address(tokenRecipient), 1, 1000, "");
        redemptionToken.mint(address(tokenRecipient), 2, 1000, "");

        target.callSale(
            newTokenId,
            redemptionMinter,
            abi.encodeWithSelector(
                ZoraCreatorTokenRedemptionMinterStrategy.setTokenRedemption.selector,
                newTokenId,
                ZoraCreatorTokenRedemptionMinterStrategy.RedemptionToken({token: address(redemptionToken), tokenId: 1}),
                ZoraCreatorTokenRedemptionMinterStrategy.RedemptionSettings({
                    ethAmountPerMint: 1 ether,
                    redemptionAmountPerMint: 500,
                    redemptionStart: 0,
                    redemptionEnd: type(uint64).max,
                    redemptionRecipient: address(0xdead),
                    fundsRecipient: address(0)
                }),
                ZoraCreatorTokenRedemptionMinterStrategy.RedemptionTokenType.ERC1155
            )
        );
        target.callSale(
            newTokenId,
            redemptionMinter,
            abi.encodeWithSelector(
                ZoraCreatorTokenRedemptionMinterStrategy.setTokenRedemption.selector,
                newTokenId,
                ZoraCreatorTokenRedemptionMinterStrategy.RedemptionToken({token: address(redemptionToken), tokenId: 2}),
                ZoraCreatorTokenRedemptionMinterStrategy.RedemptionSettings({
                    ethAmountPerMint: 1 ether,
                    redemptionAmountPerMint: 500,
                    redemptionStart: 0,
                    redemptionEnd: type(uint64).max,
                    redemptionRecipient: address(0xdead),
                    fundsRecipient: address(0)
                }),
                ZoraCreatorTokenRedemptionMinterStrategy.RedemptionTokenType.ERC1155
            )
        );

        target.callSale(newTokenId, redemptionMinter, abi.encodeWithSelector(ZoraCreatorTokenRedemptionMinterStrategy.resetSale.selector, newTokenId));

        vm.stopPrank();

        ZoraCreatorTokenRedemptionMinterStrategy.RedemptionSettings memory redemptionSettings = redemptionMinter.sale(newTokenId, address(redemptionToken), 0);
        assertEq(redemptionSettings.ethAmountPerMint, 0);
        assertEq(redemptionSettings.redemptionAmountPerMint, 0);
        assertEq(redemptionSettings.redemptionStart, 0);
        assertEq(redemptionSettings.redemptionEnd, 0);
        assertEq(redemptionSettings.redemptionRecipient, address(0));
        assertEq(redemptionSettings.fundsRecipient, address(0));

        vm.startPrank(tokenRecipient);
        redemptionToken.setApprovalForAll(address(redemptionMinter), true);
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 1;
        vm.expectRevert(abi.encodeWithSignature("NoSaleSet()"));
        target.purchase{value: 2 ether}(redemptionMinter, newTokenId, 2, abi.encode(tokenRecipient, address(redemptionToken), tokenIds));
        vm.stopPrank();
    }
}
