// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import {ZoraCreator1155Impl} from "../../src/nft/ZoraCreator1155Impl.sol";
import {ZoraCreator1155Proxy} from "../../src/proxies/ZoraCreator1155Proxy.sol";
import {IZoraCreator1155} from "../../src/interfaces/IZoraCreator1155.sol";
import {IZoraCreator1155TypesV1} from "../../src/nft/IZoraCreator1155TypesV1.sol";
import {ICreatorRoyaltiesControl} from "../../src/interfaces/ICreatorRoyaltiesControl.sol";

contract ZoraCreator1155Test is Test {
    ZoraCreator1155Impl internal zoraCreator1155Impl;
    ZoraCreator1155Impl internal target;
    address internal admin;
    address internal recipient;

    function setUp() external {
        zoraCreator1155Impl = new ZoraCreator1155Impl();
        target = ZoraCreator1155Impl(address(new ZoraCreator1155Proxy(address(zoraCreator1155Impl))));
        admin = vm.addr(0x1);
        recipient = vm.addr(0x2);
    }

    function init() internal {
        target.initialize("test", ICreatorRoyaltiesControl.RoyaltyConfiguration(0, address(0)), admin);
    }

    function init(uint32 royaltyBps, address royaltyRecipient) internal {
        target.initialize("test", ICreatorRoyaltiesControl.RoyaltyConfiguration(royaltyBps, royaltyRecipient), admin);
    }

    function test_intialize(uint32 royaltyBPS, address royaltyRecipient, address defaultAdmin) external {
        ICreatorRoyaltiesControl.RoyaltyConfiguration memory config = ICreatorRoyaltiesControl.RoyaltyConfiguration(royaltyBPS, royaltyRecipient);
        target.initialize("test", config, defaultAdmin);

        // TODO: test URI when metadata functions are complete
        // assertEq(target.uri(0), "test");
        (uint256 fetchedBps, address fetchedRecipient) = target.royalties(0);
        assertEq(fetchedBps, royaltyBPS);
        assertEq(fetchedRecipient, royaltyRecipient);
    }

    function test_initialize_revertAlreadyInitialized(uint32 royaltyBPS, address royaltyRecipient, address defaultAdmin) external {
        ICreatorRoyaltiesControl.RoyaltyConfiguration memory config = ICreatorRoyaltiesControl.RoyaltyConfiguration(royaltyBPS, royaltyRecipient);
        target.initialize("test", config, defaultAdmin);

        vm.expectRevert();
        target.initialize("test", config, defaultAdmin);
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

    function test_setTokenMetadataRenderer(string memory _uri, uint256 _maxSupply, address _renderer) external {
        init();

        vm.prank(admin);
        uint256 tokenId = target.setupNewToken(_uri, _maxSupply);

        vm.prank(admin);
        target.setTokenMetadataRenderer(1, _renderer, "");

        address renderer = target.metadataRendererContract(tokenId);
        assertEq(renderer, _renderer);
    }

    function test_setTokenMetadataRenderer_revertOnlyAdminOrRole() external {
        init();

        vm.expectRevert(abi.encodeWithSelector(IZoraCreator1155.UserMissingRoleForToken.selector, address(this), 0, target.PERMISSION_BIT_METADATA()));
        target.setTokenMetadataRenderer(0, address(0), "");
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

        vm.expectRevert(abi.encodeWithSelector(IZoraCreator1155.UserMissingRoleForToken.selector, address(this), 0, target.PERMISSION_BIT_MINTER()));
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

    function xtest_purchase(address minter, uint256 quantity, address findersRecipient) external {
        init();

        vm.prank(admin);
        uint256 tokenId = target.setupNewToken("test", quantity);

        vm.prank(admin);
        target.purchase(minter, tokenId, quantity, findersRecipient, "");

        (, , uint256 totalSupply) = target.tokens(tokenId);
        assertEq(totalSupply, 1);
        assertEq(target.balanceOf(recipient, tokenId), 1);
    }
}
