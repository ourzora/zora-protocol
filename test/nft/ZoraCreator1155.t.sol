// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import {ZoraCreator1155Impl} from "../../src/nft/ZoraCreator1155Impl.sol";
import {ZoraCreator1155Proxy} from "../../src/proxies/ZoraCreator1155Proxy.sol";
import {IZoraCreator1155} from "../../src/interfaces/IZoraCreator1155.sol";
import {IRenderer1155} from "../../src/interfaces/IRenderer1155.sol";
import {IZoraCreator1155TypesV1} from "../../src/nft/IZoraCreator1155TypesV1.sol";
import {ICreatorRoyaltiesControl} from "../../src/interfaces/ICreatorRoyaltiesControl.sol";
import {IZoraCreator1155Factory} from "../../src/interfaces/IZoraCreator1155Factory.sol";
import {SimpleMinter} from "../mock/SimpleMinter.sol";

contract ZoraCreator1155Test is Test {
    ZoraCreator1155Impl internal zoraCreator1155Impl;
    ZoraCreator1155Impl internal target;
    address internal admin;
    address internal recipient;
    uint256 internal adminRole;
    uint256 internal minterRole;
    uint256 internal fundsManagerRole;

    function setUp() external {
        zoraCreator1155Impl = new ZoraCreator1155Impl(0, address(0));
        target = ZoraCreator1155Impl(address(new ZoraCreator1155Proxy(address(zoraCreator1155Impl))));
        admin = vm.addr(0x1);
        recipient = vm.addr(0x2);
        adminRole = target.PERMISSION_BIT_ADMIN();
        minterRole = target.PERMISSION_BIT_MINTER();
        fundsManagerRole = target.PERMISSION_BIT_FUNDS_MANAGER();
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

    function test_intialize(uint32 royaltySchedule, uint32 royaltyBPS, address royaltyRecipient, address defaultAdmin) external {
        ICreatorRoyaltiesControl.RoyaltyConfiguration memory config = ICreatorRoyaltiesControl.RoyaltyConfiguration(
            royaltySchedule,
            royaltyBPS,
            royaltyRecipient
        );
        target.initialize("test", config, defaultAdmin, _emptyInitData());

        // TODO: test URI when metadata functions are complete
        // assertEq(target.uri(0), "test");
        (uint32 fetchedSchedule, uint256 fetchedBps, address fetchedRecipient) = target.royalties(0);
        assertEq(fetchedSchedule, royaltySchedule);
        assertEq(fetchedBps, royaltyBPS);
        assertEq(fetchedRecipient, royaltyRecipient);
    }

    function test_initialize_withSetupActions(
        uint32 royaltySchedule,
        uint32 royaltyBPS,
        address royaltyRecipient,
        address defaultAdmin,
        uint256 maxSupply
    ) external {
        ICreatorRoyaltiesControl.RoyaltyConfiguration memory config = ICreatorRoyaltiesControl.RoyaltyConfiguration(
            royaltySchedule,
            royaltyBPS,
            royaltyRecipient
        );
        bytes[] memory setupActions = new bytes[](1);
        setupActions[0] = abi.encodeWithSelector(IZoraCreator1155.setupNewToken.selector, "test", maxSupply);
        target.initialize("test", config, defaultAdmin, setupActions);

        (, uint256 fetchedMaxSupply, ) = target.tokens(1);
        assertEq(fetchedMaxSupply, maxSupply);
    }

    function test_initialize_revertAlreadyInitialized(uint32 royaltySchedule, uint32 royaltyBPS, address royaltyRecipient, address defaultAdmin) external {
        ICreatorRoyaltiesControl.RoyaltyConfiguration memory config = ICreatorRoyaltiesControl.RoyaltyConfiguration(
            royaltySchedule,
            royaltyBPS,
            royaltyRecipient
        );
        target.initialize("test", config, defaultAdmin, _emptyInitData());

        vm.expectRevert();
        target.initialize("test", config, defaultAdmin, _emptyInitData());
    }

    function test_setupNewToken_asAdmin(string memory _uri, uint256 _maxSupply) external {
        init();

        vm.prank(admin);
        uint256 tokenId = target.setupNewToken(_uri, _maxSupply);

        (string memory uri, uint256 maxSupply, uint256 totalSupply) = target.tokens(tokenId);

        assertEq(uri, _uri);
        assertEq(maxSupply, _maxSupply);
        assertEq(totalSupply, 0);
    }

    function xtest_setupNewToken_asMinter(string memory _uri, uint256 _maxSupply) external {}

    function test_setupNewToken_revertOnlyAdminOrRole() external {
        init();

        vm.expectRevert(abi.encodeWithSelector(IZoraCreator1155.UserMissingRoleForToken.selector, address(this), 0, target.PERMISSION_BIT_MINTER()));
        target.setupNewToken("test", 1);
    }

    // function test_setTokenMetadataRenderer(
    //     string memory _uri,
    //     uint256 _maxSupply,
    //     address _renderer
    // ) external {
    //     init();

    //     vm.prank(admin);
    //     uint256 tokenId = target.setupNewToken(_uri, _maxSupply);

    //     vm.prank(admin);
    //     target.setTokenMetadataRenderer(1, IRenderer1155(_renderer), "");

    //     address renderer = target.metadataRendererContract(tokenId);
    //     assertEq(renderer, _renderer);
    // }

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

        (, , uint256 totalSupply) = target.tokens(tokenId);
        assertEq(totalSupply, quantity);
        assertEq(target.balanceOf(recipient, tokenId), quantity);
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

        vm.expectRevert(abi.encodeWithSelector(IZoraCreator1155.CannotMintMoreTokens.selector, tokenId));
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

        (, , uint256 totalSupply1) = target.tokens(tokenId1);
        (, , uint256 totalSupply2) = target.tokens(tokenId2);

        assertEq(totalSupply1, quantity1);
        assertEq(totalSupply2, quantity2);
        assertEq(target.balanceOf(recipient, tokenId1), quantity1);
        assertEq(target.balanceOf(recipient, tokenId2), quantity2);
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

        vm.expectRevert(abi.encodeWithSelector(IZoraCreator1155.CannotMintMoreTokens.selector, tokenId));
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

    function test_purchase(uint256 quantity) external {
        init();

        vm.prank(admin);
        uint256 tokenId = target.setupNewToken("test", quantity);

        SimpleMinter minter = new SimpleMinter();
        vm.prank(admin);
        target.addPermission(tokenId, address(minter), adminRole);

        vm.prank(admin);
        target.purchase(minter, tokenId, quantity, abi.encode(recipient));

        (, , uint256 totalSupply) = target.tokens(tokenId);
        assertEq(totalSupply, quantity);
        assertEq(target.balanceOf(recipient, tokenId), quantity);
    }

    function test_purchase_revertOnlyMinter() external {
        init();

        vm.prank(admin);
        uint256 tokenId = target.setupNewToken("test", 1000);

        vm.expectRevert(abi.encodeWithSelector(IZoraCreator1155.UserMissingRoleForToken.selector, address(0), tokenId, target.PERMISSION_BIT_MINTER()));
        target.purchase(SimpleMinter(payable(address(0))), tokenId, 0, "");
    }

    function test_purchase_revertCannotMintMoreTokens() external {
        init();

        vm.prank(admin);
        uint256 tokenId = target.setupNewToken("test", 1000);

        SimpleMinter minter = new SimpleMinter();
        vm.prank(admin);
        target.addPermission(tokenId, address(minter), adminRole);

        vm.expectRevert(abi.encodeWithSelector(IZoraCreator1155.CannotMintMoreTokens.selector, tokenId));
        vm.prank(admin);
        target.purchase(minter, tokenId, 1001, abi.encode(recipient));
    }

    function test_supportsInterface() external {
        init();

        bytes4 interfaceId = type(IZoraCreator1155).interfaceId;

        assertEq(target.supportsInterface(interfaceId), true);
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
        target.purchase{value: 1 ether}(minter, tokenId, 1000, abi.encode(recipient));

        vm.prank(admin);
        target.withdrawAll();

        assertEq(admin.balance, 1 ether);
    }

    function test_withdrawAll_revertETHWtihdrawFailed(uint256 purchaseAmount, uint256 withdrawAmount) external {
        vm.assume(withdrawAmount <= purchaseAmount);
        init();

        vm.prank(admin);
        uint256 tokenId = target.setupNewToken("test", 1000);

        SimpleMinter minter = new SimpleMinter();
        SimpleMinter(payable(minter)).setReceiveETH(false);

        vm.prank(admin);
        target.addPermission(tokenId, address(minter), minterRole);

        vm.prank(admin);
        target.addPermission(0, address(minter), fundsManagerRole);

        vm.deal(admin, 1 ether);
        vm.prank(admin);
        target.purchase{value: 1 ether}(minter, tokenId, 1000, abi.encode(recipient));

        vm.expectRevert(abi.encodeWithSelector(IZoraCreator1155.ETHWithdrawFailed.selector, minter, 1 ether));
        vm.prank(address(minter));
        target.withdrawAll();
    }

    function test_withdrawCustom(uint256 purchaseAmount, uint256 withdrawAmount) external {
        vm.assume(withdrawAmount <= purchaseAmount);
        init();

        vm.prank(admin);
        uint256 tokenId = target.setupNewToken("test", 1000);

        SimpleMinter minter = new SimpleMinter();
        vm.prank(admin);
        target.addPermission(tokenId, address(minter), minterRole);

        vm.deal(admin, purchaseAmount);
        vm.prank(admin);
        target.purchase{value: purchaseAmount}(minter, tokenId, 1000, abi.encode(recipient));

        console.log("recipient balance before ", recipient.balance);
        vm.prank(admin);
        target.withdrawCustom(recipient, withdrawAmount);
        console.log("recipient balance after ", recipient.balance);

        // a withdraw amount of 0 is treated as a withdrawAll()
        assertEq(recipient.balance, withdrawAmount == 0 ? purchaseAmount : withdrawAmount);
        assertEq(address(target).balance, withdrawAmount == 0 ? 0 : purchaseAmount - withdrawAmount);
    }

    function test_withdrawCustom_revertFundsWithdrawInsolvent(uint256 purchaseAmount, uint256 withdrawAmount) external {
        vm.assume(withdrawAmount > purchaseAmount);
        init();

        vm.prank(admin);
        uint256 tokenId = target.setupNewToken("test", 1000);

        SimpleMinter minter = new SimpleMinter();
        vm.prank(admin);
        target.addPermission(tokenId, address(minter), minterRole);

        vm.deal(admin, purchaseAmount);
        vm.prank(admin);
        target.purchase{value: purchaseAmount}(minter, tokenId, 1000, abi.encode(recipient));

        vm.expectRevert(abi.encodeWithSelector(IZoraCreator1155.FundsWithdrawInsolvent.selector, withdrawAmount, purchaseAmount));
        vm.prank(admin);
        target.withdrawCustom(address(minter), withdrawAmount);
    }

    function test_withdrawCustom_revertETHWithdrawFailed() external {
        init();

        vm.prank(admin);
        uint256 tokenId = target.setupNewToken("test", 1000);

        SimpleMinter minter = new SimpleMinter();
        minter.setReceiveETH(false);

        vm.prank(admin);
        target.addPermission(tokenId, address(minter), minterRole);

        vm.deal(admin, 1 ether);
        vm.prank(admin);
        target.purchase{value: 1 ether}(minter, tokenId, 1000, abi.encode(recipient));

        vm.expectRevert(abi.encodeWithSelector(IZoraCreator1155.ETHWithdrawFailed.selector, minter, 1 ether));
        vm.prank(admin);
        target.withdrawCustom(address(minter), 1 ether);
    }
}
