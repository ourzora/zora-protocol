// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import {ZoraCreator1155Impl} from "../../src/nft/ZoraCreator1155Impl.sol";
import {Zora1155} from "../../src/proxies/Zora1155.sol";
import {IZoraCreator1155} from "../../src/interfaces/IZoraCreator1155.sol";
import {IRenderer1155} from "../../src/interfaces/IRenderer1155.sol";
import {IZoraCreator1155TypesV1} from "../../src/nft/IZoraCreator1155TypesV1.sol";
import {ICreatorRoyaltiesControl} from "../../src/interfaces/ICreatorRoyaltiesControl.sol";
import {IZoraCreator1155Factory} from "../../src/interfaces/IZoraCreator1155Factory.sol";
import {ICreatorRendererControl} from "../../src/interfaces/ICreatorRendererControl.sol";
import {SimpleMinter} from "../mock/SimpleMinter.sol";
import {SimpleRenderer} from "../mock/SimpleRenderer.sol";

contract ZoraCreator1155Test is Test {
    ZoraCreator1155Impl internal zoraCreator1155Impl;
    ZoraCreator1155Impl internal target;
    address payable internal admin;
    address internal recipient;
    uint256 internal adminRole;
    uint256 internal minterRole;
    uint256 internal fundsManagerRole;
    uint256 internal metadataRole;

    function setUp() external {
        zoraCreator1155Impl = new ZoraCreator1155Impl(0, address(0));
        target = ZoraCreator1155Impl(address(new Zora1155(address(zoraCreator1155Impl))));
        admin = payable(vm.addr(0x1));
        recipient = vm.addr(0x2);
        adminRole = target.PERMISSION_BIT_ADMIN();
        minterRole = target.PERMISSION_BIT_MINTER();
        fundsManagerRole = target.PERMISSION_BIT_FUNDS_MANAGER();
        metadataRole = target.PERMISSION_BIT_METADATA();
    }

    function _emptyInitData() internal pure returns (bytes[] memory response) {
        response = new bytes[](0);
    }

    function init() internal {
        target.initialize("test", ICreatorRoyaltiesControl.RoyaltyConfiguration(0, 0, address(0)), admin, _emptyInitData());
    }

    function init(uint32 royaltySchedule, uint32 royaltyBps, address royaltyRecipient) internal {
        target.initialize("test", ICreatorRoyaltiesControl.RoyaltyConfiguration(royaltySchedule, royaltyBps, royaltyRecipient), admin, _emptyInitData());
    }

    function test_initialize(uint32 royaltySchedule, uint32 royaltyBPS, address royaltyRecipient, address payable defaultAdmin) external {
        vm.assume(royaltySchedule != 1);
        ICreatorRoyaltiesControl.RoyaltyConfiguration memory config = ICreatorRoyaltiesControl.RoyaltyConfiguration(
            royaltySchedule,
            royaltyBPS,
            royaltyRecipient
        );
        target.initialize("test", config, defaultAdmin, _emptyInitData());

        assertEq(target.contractURI(), "test");
        (uint32 fetchedSchedule, uint256 fetchedBps, address fetchedRecipient) = target.royalties(0);
        assertEq(fetchedSchedule, royaltySchedule);
        assertEq(fetchedBps, royaltyBPS);
        assertEq(fetchedRecipient, royaltyRecipient);
    }

    function test_initialize_withSetupActions(
        uint32 royaltySchedule,
        uint32 royaltyBPS,
        address royaltyRecipient,
        address payable defaultAdmin,
        uint256 maxSupply
    ) external {
        vm.assume(royaltySchedule != 1);
        ICreatorRoyaltiesControl.RoyaltyConfiguration memory config = ICreatorRoyaltiesControl.RoyaltyConfiguration(
            royaltySchedule,
            royaltyBPS,
            royaltyRecipient
        );
        bytes[] memory setupActions = new bytes[](1);
        setupActions[0] = abi.encodeWithSelector(IZoraCreator1155.setupNewToken.selector, "test", maxSupply);
        target.initialize("test", config, defaultAdmin, setupActions);

        IZoraCreator1155TypesV1.TokenData memory tokenData = target.getTokenInfo(1);
        assertEq(tokenData.maxSupply, maxSupply);
    }

    function test_initialize_revertAlreadyInitialized(
        uint32 royaltySchedule,
        uint32 royaltyBPS,
        address royaltyRecipient,
        address payable defaultAdmin
    ) external {
        vm.assume(royaltySchedule != 1);
        ICreatorRoyaltiesControl.RoyaltyConfiguration memory config = ICreatorRoyaltiesControl.RoyaltyConfiguration(
            royaltySchedule,
            royaltyBPS,
            royaltyRecipient
        );
        target.initialize("test", config, defaultAdmin, _emptyInitData());

        vm.expectRevert();
        target.initialize("test", config, defaultAdmin, _emptyInitData());
    }

    function test_contractVersion() external {
        init();

        assertEq(target.contractVersion(), "0.0.8");
    }

    function test_assumeLastTokenIdMatches() external {
        init();

        vm.prank(admin);
        uint256 tokenId = target.setupNewToken("test", 1);
        assertEq(tokenId, 1);
        target.assumeLastTokenIdMatches(tokenId);

        vm.expectRevert(abi.encodeWithSignature("TokenIdMismatch(uint256,uint256)", 2, 1));
        target.assumeLastTokenIdMatches(2);
    }

    function test_isAdminOrRole() external {
        init();

        vm.prank(admin);
        uint256 tokenId = target.setupNewToken("test", 1);

        assertEq(target.isAdminOrRole(admin, tokenId, adminRole), true);
        assertEq(target.isAdminOrRole(admin, tokenId, minterRole), true);
        assertEq(target.isAdminOrRole(admin, tokenId, fundsManagerRole), true);
        assertEq(target.isAdminOrRole(admin, 2, adminRole), false);
        assertEq(target.isAdminOrRole(recipient, tokenId, adminRole), false);
    }

    function test_setupNewToken_asAdmin(string memory newURI, uint256 _maxSupply) external {
        init();

        vm.prank(admin);
        uint256 tokenId = target.setupNewToken(newURI, _maxSupply);

        IZoraCreator1155TypesV1.TokenData memory tokenData = target.getTokenInfo(tokenId);

        assertEq(tokenData.uri, newURI);
        assertEq(tokenData.maxSupply, _maxSupply);
        assertEq(tokenData.totalMinted, 0);
    }

    function xtest_setupNewToken_asMinter(string memory newURI, uint256 _maxSupply) external {}

    function test_setupNewToken_revertOnlyAdminOrRole() external {
        init();

        vm.expectRevert(abi.encodeWithSelector(IZoraCreator1155.UserMissingRoleForToken.selector, address(this), 0, target.PERMISSION_BIT_MINTER()));
        target.setupNewToken("test", 1);
    }

    function test_updateTokenURI() external {
        init();

        vm.prank(admin);
        uint256 tokenId = target.setupNewToken("test", 1);
        assertEq(target.uri(tokenId), "test");

        vm.prank(admin);
        target.updateTokenURI(tokenId, "test2");
        assertEq(target.uri(tokenId), "test2");
    }

    function test_setTokenMetadataRenderer() external {
        target.initialize("", ICreatorRoyaltiesControl.RoyaltyConfiguration(0, 0, address(0)), admin, _emptyInitData());

        SimpleRenderer contractRenderer = new SimpleRenderer();
        contractRenderer.setContractURI("contract renderer");
        SimpleRenderer singletonRenderer = new SimpleRenderer();

        vm.startPrank(admin);
        target.setTokenMetadataRenderer(0, contractRenderer, "fallback renderer");
        uint256 tokenId = target.setupNewToken("", 1);
        target.setTokenMetadataRenderer(tokenId, singletonRenderer, "singleton renderer");
        vm.stopPrank();

        assertEq(address(target.getCustomRenderer(0)), address(contractRenderer));
        assertEq(target.contractURI(), "contract renderer");
        assertEq(address(target.getCustomRenderer(tokenId)), address(singletonRenderer));
        assertEq(target.uri(tokenId), "singleton renderer");

        vm.prank(admin);
        target.setTokenMetadataRenderer(tokenId, IRenderer1155(address(0)), "");
        assertEq(address(target.getCustomRenderer(tokenId)), address(contractRenderer));
        assertEq(target.uri(tokenId), "fallback renderer");
    }

    function test_setTokenMetadataRenderer_revertOnlyAdminOrRole() external {
        init();

        vm.expectRevert(abi.encodeWithSelector(IZoraCreator1155.UserMissingRoleForToken.selector, address(this), 0, target.PERMISSION_BIT_METADATA()));
        target.setTokenMetadataRenderer(0, IRenderer1155(address(0)), "");
    }

    function test_addPermission(uint256 tokenId, uint256 permission, address user) external {
        vm.assume(permission != 0);
        init();

        vm.prank(admin);
        target.setupNewToken("test", 1000);

        vm.prank(admin);
        target.addPermission(tokenId, user, permission);

        assertEq(target.getPermissions(tokenId, user), permission);
    }

    function test_addPermission_revertOnlyAdminOrRole(uint256 tokenId) external {
        vm.assume(tokenId != 0);
        init();

        vm.expectRevert(abi.encodeWithSelector(IZoraCreator1155.UserMissingRoleForToken.selector, recipient, tokenId, adminRole));
        vm.prank(recipient);
        target.addPermission(tokenId, recipient, adminRole);
    }

    function test_removePermission(uint256 tokenId, uint256 permission, address user) external {
        vm.assume(permission != 0);
        init();

        vm.prank(admin);
        target.setupNewToken("test", 1000);

        vm.prank(admin);
        target.addPermission(tokenId, user, permission);

        vm.prank(admin);
        target.removePermission(tokenId, user, permission);

        assertEq(target.getPermissions(tokenId, user), 0);
    }

    function test_removePermissionRevokeOwnership() external {
        init();

        assertEq(target.owner(), admin);

        vm.prank(admin);
        target.removePermission(0, admin, adminRole);
        assertEq(target.owner(), address(0));
    }

    function test_setOwner() external {
        init();

        assertEq(target.owner(), admin);

        vm.startPrank(admin);
        vm.expectRevert(abi.encodeWithSignature("NewOwnerNeedsToBeAdmin()"));
        target.setOwner(recipient);

        target.addPermission(0, recipient, adminRole);
        target.setOwner(recipient);
        assertEq(target.owner(), recipient);

        vm.stopPrank();
    }

    function test_removePermission_revertOnlyAdminOrRole(uint256 tokenId) external {
        vm.assume(tokenId != 0);
        init();

        vm.expectRevert(abi.encodeWithSelector(IZoraCreator1155.UserMissingRoleForToken.selector, recipient, tokenId, adminRole));
        vm.prank(recipient);
        target.removePermission(tokenId, address(0), adminRole);
    }

    function test_adminMint(uint256 quantity) external {
        vm.assume(quantity < 1000);
        init();

        vm.prank(admin);
        uint256 tokenId = target.setupNewToken("test", 1000);

        vm.prank(admin);
        target.adminMint(recipient, tokenId, quantity, "");

        IZoraCreator1155TypesV1.TokenData memory tokenData = target.getTokenInfo(tokenId);
        assertEq(tokenData.totalMinted, quantity);
        assertEq(target.balanceOf(recipient, tokenId), quantity);
    }

    function test_adminMintWithScheduleSmall() external {
        uint256 quantity = 100;
        address royaltyRecipient = address(0x3334);
        // every 10 royalty 100/10 = 10 tokens minted
        init(10, 0, royaltyRecipient);

        vm.prank(admin);
        uint256 tokenId = target.setupNewToken("test", quantity);

        vm.prank(admin);
        target.adminMint(recipient, tokenId, 90, "");

        IZoraCreator1155TypesV1.TokenData memory tokenData = target.getTokenInfo(tokenId);
        assertEq(tokenData.totalMinted, 100);
        assertEq(target.balanceOf(recipient, tokenId), (quantity * 9) / 10);
        assertEq(target.balanceOf(royaltyRecipient, tokenId), (quantity * 1) / 10);
    }

    function test_adminMintWithSchedule() external {
        uint256 quantity = 1000;
        address royaltyRecipient = address(0x3334);
        // every 10 tokens, mint 1 to  royalty 1000/10 = 100 tokens minted to royalty recipient
        init(10, 0, royaltyRecipient);

        vm.prank(admin);
        uint256 tokenId = target.setupNewToken("test", 1000);

        vm.prank(admin);
        target.adminMint(recipient, tokenId, (quantity * 9) / 10, "");

        IZoraCreator1155TypesV1.TokenData memory tokenData = target.getTokenInfo(tokenId);
        assertEq(tokenData.totalMinted, 1000);
        assertEq(target.balanceOf(recipient, tokenId), (quantity * 9) / 10);
        assertEq(target.balanceOf(royaltyRecipient, tokenId), (quantity * 1) / 10);
    }

    function test_adminMint_revertOnlyAdminOrRole() external {
        init();

        vm.prank(admin);
        uint256 tokenId = target.setupNewToken("test", 1000);

        vm.expectRevert(abi.encodeWithSelector(IZoraCreator1155.UserMissingRoleForToken.selector, address(this), tokenId, target.PERMISSION_BIT_MINTER()));
        target.adminMint(address(0), tokenId, 0, "");
    }

    function test_adminMint_revertMaxSupply(uint256 quantity) external {
        vm.assume(quantity > 0);
        init();

        vm.prank(admin);
        uint256 tokenId = target.setupNewToken("test", quantity - 1);

        vm.expectRevert(abi.encodeWithSelector(IZoraCreator1155.CannotMintMoreTokens.selector, tokenId, quantity, 0, quantity - 1));
        vm.prank(admin);
        target.adminMint(recipient, tokenId, quantity, "");
    }

    function test_adminMint_revertZeroAddressRecipient() external {
        init();

        vm.prank(admin);
        uint256 tokenId = target.setupNewToken("test", 1000);

        vm.expectRevert();
        vm.prank(admin);
        target.adminMint(address(0), tokenId, 0, "");
    }

    function test_adminMintBatch(uint256 quantity1, uint256 quantity2) external {
        vm.assume(quantity1 < 1000);
        vm.assume(quantity2 < 1000);
        init();

        vm.prank(admin);
        uint256 tokenId1 = target.setupNewToken("test", 1000);

        vm.prank(admin);
        uint256 tokenId2 = target.setupNewToken("test", 1000);

        uint256[] memory tokenIds = new uint256[](2);
        uint256[] memory quantities = new uint256[](2);
        tokenIds[0] = tokenId1;
        tokenIds[1] = tokenId2;
        quantities[0] = quantity1;
        quantities[1] = quantity2;

        vm.prank(admin);
        target.adminMintBatch(recipient, tokenIds, quantities, "");

        IZoraCreator1155TypesV1.TokenData memory tokenData1 = target.getTokenInfo(tokenId1);
        IZoraCreator1155TypesV1.TokenData memory tokenData2 = target.getTokenInfo(tokenId2);

        assertEq(tokenData1.totalMinted, quantity1);
        assertEq(tokenData2.totalMinted, quantity2);
        assertEq(target.balanceOf(recipient, tokenId1), quantity1);
        assertEq(target.balanceOf(recipient, tokenId2), quantity2);
    }

    function test_adminMintBatchWithSchedule(uint256 quantity1, uint256 quantity2) external {
        vm.assume(quantity1 < 900);
        vm.assume(quantity2 < 900);

        address royaltyRecipient = address(0x3334);
        // every 10th token is a token for the royalty recipient
        init(10, 0, royaltyRecipient);

        vm.prank(admin);
        uint256 tokenId1 = target.setupNewToken("test", 1000);

        vm.prank(admin);
        uint256 tokenId2 = target.setupNewToken("test", 1000);

        uint256[] memory tokenIds = new uint256[](2);
        uint256[] memory quantities = new uint256[](2);
        tokenIds[0] = tokenId1;
        tokenIds[1] = tokenId2;
        quantities[0] = quantity1;
        quantities[1] = quantity2;

        vm.prank(admin);
        target.adminMintBatch(recipient, tokenIds, quantities, "");

        IZoraCreator1155TypesV1.TokenData memory tokenData1 = target.getTokenInfo(tokenId1);
        IZoraCreator1155TypesV1.TokenData memory tokenData2 = target.getTokenInfo(tokenId2);

        assertEq(tokenData1.totalMinted, quantity1 + (quantity1 / 9));
        assertEq(tokenData2.totalMinted, quantity2 + (quantity2 / 9));
        assertEq(target.balanceOf(recipient, tokenId1), quantity1);
        assertEq(target.balanceOf(recipient, tokenId2), quantity2);
        assertEq(target.balanceOf(royaltyRecipient, tokenId1), quantity1 / 9);
        assertEq(target.balanceOf(royaltyRecipient, tokenId2), quantity2 / 9);
    }

    function test_adminMintBatch_revertOnlyAdminOrRole() external {
        init();

        vm.prank(admin);
        uint256 tokenId = target.setupNewToken("test", 1000);

        uint256[] memory tokenIds = new uint256[](1);
        uint256[] memory quantities = new uint256[](1);
        tokenIds[0] = tokenId;
        quantities[0] = 0;

        vm.expectRevert(abi.encodeWithSelector(IZoraCreator1155.UserMissingRoleForToken.selector, address(this), tokenId, target.PERMISSION_BIT_MINTER()));
        target.adminMintBatch(address(0), tokenIds, quantities, "");
    }

    function test_adminMintBatch_revertMaxSupply(uint256 quantity) external {
        vm.assume(quantity > 1);
        init();

        vm.prank(admin);
        uint256 tokenId = target.setupNewToken("test", quantity - 1);

        uint256[] memory tokenIds = new uint256[](1);
        uint256[] memory quantities = new uint256[](1);
        tokenIds[0] = tokenId;
        quantities[0] = quantity;

        vm.expectRevert(abi.encodeWithSelector(IZoraCreator1155.CannotMintMoreTokens.selector, tokenId, quantity, 0, quantity - 1));
        vm.prank(admin);
        target.adminMintBatch(recipient, tokenIds, quantities, "");
    }

    function test_adminMintBatch_revertZeroAddressRecipient() external {
        init();

        vm.prank(admin);
        uint256 tokenId = target.setupNewToken("test", 1000);

        uint256[] memory tokenIds = new uint256[](1);
        uint256[] memory quantities = new uint256[](1);
        tokenIds[0] = tokenId;
        quantities[0] = 0;

        vm.expectRevert();
        vm.prank(admin);
        target.adminMintBatch(address(0), tokenIds, quantities, "");
    }

    function test_mint(uint256 quantity) external {
        init();

        vm.prank(admin);
        uint256 tokenId = target.setupNewToken("test", quantity);

        SimpleMinter minter = new SimpleMinter();
        vm.prank(admin);
        target.addPermission(tokenId, address(minter), adminRole);

        vm.prank(admin);
        target.mint(minter, tokenId, quantity, abi.encode(recipient));

        IZoraCreator1155TypesV1.TokenData memory tokenData = target.getTokenInfo(tokenId);
        assertEq(tokenData.totalMinted, quantity);
        assertEq(target.balanceOf(recipient, tokenId), quantity);
    }

    function test_mint_revertOnlyMinter() external {
        init();

        vm.prank(admin);
        uint256 tokenId = target.setupNewToken("test", 1000);

        vm.expectRevert(abi.encodeWithSelector(IZoraCreator1155.UserMissingRoleForToken.selector, address(0), tokenId, target.PERMISSION_BIT_MINTER()));
        target.mint(SimpleMinter(payable(address(0))), tokenId, 0, "");
    }

    function test_mint_revertCannotMintMoreTokens() external {
        init();

        vm.prank(admin);
        uint256 tokenId = target.setupNewToken("test", 1000);

        SimpleMinter minter = new SimpleMinter();
        vm.prank(admin);
        target.addPermission(tokenId, address(minter), adminRole);

        vm.expectRevert(abi.encodeWithSelector(IZoraCreator1155.CannotMintMoreTokens.selector, tokenId, 1001, 0, 1000));
        vm.prank(admin);
        target.mint(minter, tokenId, 1001, abi.encode(recipient));
    }

    function test_callSale() external {
        init();

        SimpleMinter minter = new SimpleMinter();

        vm.startPrank(admin);

        uint256 tokenId = target.setupNewToken("", 1);
        target.addPermission(tokenId, address(minter), minterRole);

        target.callSale(tokenId, minter, abi.encodeWithSignature("setNum(uint256)", 1));
        assertEq(minter.num(), 1);

        vm.expectRevert(abi.encodeWithSignature("Sale_CallFailed()"));
        target.callSale(tokenId, minter, abi.encodeWithSignature("setNum(uint256)", 0));

        vm.stopPrank();
    }

    function test_callRenderer() external {
        init();

        SimpleRenderer renderer = new SimpleRenderer();

        vm.startPrank(admin);

        uint256 tokenId = target.setupNewToken("", 1);
        target.setTokenMetadataRenderer(tokenId, renderer, "renderer");
        assertEq(target.uri(tokenId), "renderer");

        target.callRenderer(tokenId, abi.encodeWithSignature("setup(bytes)", "callRender successful"));
        assertEq(target.uri(tokenId), "callRender successful");

        vm.expectRevert(abi.encodeWithSelector(IZoraCreator1155.Renderer_CallFailed.selector, ""));
        target.callRenderer(tokenId, abi.encodeWithSelector(SimpleRenderer.setup.selector, ""));

        vm.stopPrank();
    }

    function test_UpdateContractMetadataFailsContract() external {
        init();

        vm.expectRevert(IZoraCreator1155.NotAllowedContractBaseIDUpdate.selector);
        vm.prank(admin);
        target.updateTokenURI(0, "test");
    }

    function test_ContractNameUpdate() external {
        init();
        assertEq(target.name(), "");

        vm.prank(admin);
        target.updateContractMetadata("newURI", "ASDF");
        assertEq(target.name(), "ASDF");
    }

    function test_TokenURI() external {
        init();

        vm.prank(admin);
        uint256 tokenId = target.setupNewToken("mockuri", 1);
        assertEq(target.uri(tokenId), "mockuri");
    }

    function test_callSetupRendererFails() external {
        init();

        SimpleRenderer renderer = SimpleRenderer(address(new SimpleMinter()));

        vm.startPrank(admin);
        uint256 tokenId = target.setupNewToken("", 1);
        vm.expectRevert(abi.encodeWithSelector(ICreatorRendererControl.RendererNotValid.selector, address(renderer)));
        target.setTokenMetadataRenderer(tokenId, renderer, "renderer");
    }

    function test_callRendererFails() external {
        init();

        SimpleRenderer renderer = new SimpleRenderer();

        vm.startPrank(admin);
        uint256 tokenId = target.setupNewToken("", 1);
        target.setTokenMetadataRenderer(tokenId, renderer, "renderer");

        vm.expectRevert(abi.encodeWithSelector(IZoraCreator1155.Renderer_CallFailed.selector, ""));
        target.callRenderer(tokenId, "0xfoobar");
    }

    function test_supportsInterface() external {
        init();

        // TODO: make this static
        bytes4 interfaceId = type(IZoraCreator1155).interfaceId;

        assertEq(target.supportsInterface(interfaceId), true);
    }

    function test_burnBatch() external {
        init();

        vm.prank(admin);
        uint256 tokenId = target.setupNewToken("test", 10);

        SimpleMinter minter = new SimpleMinter();
        vm.prank(admin);
        target.addPermission(tokenId, address(minter), adminRole);

        vm.prank(admin);
        target.mint(minter, tokenId, 5, abi.encode(recipient));

        uint256[] memory burnBatchIds = new uint256[](1);
        uint256[] memory burnBatchValues = new uint256[](1);
        burnBatchIds[0] = tokenId;
        burnBatchValues[0] = 3;

        vm.prank(recipient);
        target.burnBatch(recipient, burnBatchIds, burnBatchValues);
    }

    function test_burnBatch_user_not_approved_fails() external {
        init();

        vm.prank(admin);
        uint256 tokenId = target.setupNewToken("test", 10);

        SimpleMinter minter = new SimpleMinter();
        vm.prank(admin);
        target.addPermission(tokenId, address(minter), adminRole);

        vm.prank(admin);
        target.mint(minter, tokenId, 5, abi.encode(recipient));

        uint256[] memory burnBatchIds = new uint256[](1);
        uint256[] memory burnBatchValues = new uint256[](1);
        burnBatchIds[0] = tokenId;
        burnBatchValues[0] = 3;

        vm.expectRevert();

        vm.prank(address(0x123));
        target.burnBatch(recipient, burnBatchIds, burnBatchValues);
    }

    function test_withdrawAll() external {
        init();

        vm.prank(admin);
        uint256 tokenId = target.setupNewToken("test", 1000);

        SimpleMinter minter = new SimpleMinter();
        vm.prank(admin);
        target.addPermission(tokenId, address(minter), minterRole);

        vm.deal(admin, 1 ether);
        vm.prank(admin);
        target.mint{value: 1 ether}(minter, tokenId, 1000, abi.encode(recipient));

        vm.prank(admin);
        target.withdraw();

        assertEq(admin.balance, 1 ether);
    }

    function test_withdrawAll_revertETHWithdrawFailed(uint256 purchaseAmount, uint256 withdrawAmount) external {
        vm.assume(withdrawAmount <= purchaseAmount);
        init();

        vm.prank(admin);
        uint256 tokenId = target.setupNewToken("test", 1000);

        SimpleMinter minter = new SimpleMinter();
        SimpleMinter(payable(minter)).setReceiveETH(false);

        vm.prank(admin);
        target.setFundsRecipient(payable(minter));

        vm.prank(admin);
        target.addPermission(tokenId, address(minter), minterRole);

        vm.prank(admin);
        target.addPermission(0, address(minter), fundsManagerRole);

        vm.deal(admin, 1 ether);
        vm.prank(admin);
        target.mint{value: 1 ether}(minter, tokenId, 1000, abi.encode(recipient));

        vm.expectRevert(abi.encodeWithSelector(IZoraCreator1155.ETHWithdrawFailed.selector, minter, 1 ether));
        vm.prank(address(minter));
        target.withdraw();
    }
}
