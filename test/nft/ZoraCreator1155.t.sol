// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import {ProtocolRewards} from "@zoralabs/protocol-rewards/src/ProtocolRewards.sol";
import {RewardsSettings} from "@zoralabs/protocol-rewards/src/abstract/RewardSplits.sol";
import {MathUpgradeable} from "@zoralabs/openzeppelin-contracts-upgradeable/contracts/utils/math/MathUpgradeable.sol";
import {ZoraCreator1155Impl} from "../../src/nft/ZoraCreator1155Impl.sol";
import {ITransferHookReceiver} from "../../src/interfaces/ITransferHookReceiver.sol";
import {Zora1155} from "../../src/proxies/Zora1155.sol";
import {ZoraCreatorFixedPriceSaleStrategy} from "../../src/minters/fixed-price/ZoraCreatorFixedPriceSaleStrategy.sol";
import {UpgradeGate} from "../../src/upgrades/UpgradeGate.sol";
import {PremintConfig, TokenCreationConfig} from "../../src/delegation/ZoraCreator1155Attribution.sol";
import {ZoraCreator1155Attribution} from "../../src/delegation/ZoraCreator1155Attribution.sol";

import {IZoraCreator1155Errors} from "../../src/interfaces/IZoraCreator1155Errors.sol";
import {IZoraCreator1155} from "../../src/interfaces/IZoraCreator1155.sol";
import {IRenderer1155} from "../../src/interfaces/IRenderer1155.sol";
import {IZoraCreator1155TypesV1} from "../../src/nft/IZoraCreator1155TypesV1.sol";
import {ICreatorRoyaltiesControl} from "../../src/interfaces/ICreatorRoyaltiesControl.sol";
import {IZoraCreator1155Factory} from "../../src/interfaces/IZoraCreator1155Factory.sol";
import {ICreatorRendererControl} from "../../src/interfaces/ICreatorRendererControl.sol";

import {SimpleMinter} from "../mock/SimpleMinter.sol";
import {SimpleRenderer} from "../mock/SimpleRenderer.sol";

contract MockTransferHookReceiver is ITransferHookReceiver {
    mapping(uint256 => bool) public hasTransfer;

    function onTokenTransferBatch(
        address target,
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) external {
        for (uint256 i = 0; i < ids.length; i++) {
            hasTransfer[ids[i]] = true;
        }
    }

    function onTokenTransfer(address target, address operator, address from, address to, uint256 id, uint256 amount, bytes memory data) external {
        hasTransfer[id] = true;
    }

    function supportsInterface(bytes4 testInterface) external view override returns (bool) {
        return testInterface == type(ITransferHookReceiver).interfaceId;
    }
}

contract ZoraCreator1155Test is Test {
    using stdJson for string;

    ProtocolRewards internal protocolRewards;
    ZoraCreator1155Impl internal zoraCreator1155Impl;
    ZoraCreator1155Impl internal target;

    SimpleMinter simpleMinter;
    ZoraCreatorFixedPriceSaleStrategy internal fixedPriceMinter;
    UpgradeGate internal upgradeGate;

    address payable internal admin;
    uint256 internal adminKey;
    address internal recipient;
    uint256 internal adminRole;
    uint256 internal minterRole;
    uint256 internal fundsManagerRole;
    uint256 internal metadataRole;

    address internal creator;
    address internal collector;
    address internal mintReferral;
    address internal createReferral;
    address internal zora;

    event Purchased(address indexed sender, address indexed minter, uint256 indexed tokenId, uint256 quantity, uint256 value);

    function setUp() external {
        creator = makeAddr("creator");
        collector = makeAddr("collector");
        mintReferral = makeAddr("mintReferral");
        createReferral = makeAddr("createReferral");
        zora = makeAddr("zora");

        address adminAddress;
        (adminAddress, adminKey) = makeAddrAndKey("admin");
        admin = payable(adminAddress);
        recipient = vm.addr(0x2);

        protocolRewards = new ProtocolRewards();
        upgradeGate = new UpgradeGate();
        upgradeGate.initialize(admin);
        zoraCreator1155Impl = new ZoraCreator1155Impl(zora, address(upgradeGate), address(protocolRewards));
        target = ZoraCreator1155Impl(address(new Zora1155(address(zoraCreator1155Impl))));
        simpleMinter = new SimpleMinter();
        fixedPriceMinter = new ZoraCreatorFixedPriceSaleStrategy();

        adminRole = target.PERMISSION_BIT_ADMIN();
        minterRole = target.PERMISSION_BIT_MINTER();
        fundsManagerRole = target.PERMISSION_BIT_FUNDS_MANAGER();
        metadataRole = target.PERMISSION_BIT_METADATA();
    }

    function _emptyInitData() internal pure returns (bytes[] memory response) {
        response = new bytes[](0);
    }

    function init() internal {
        target.initialize("test", "test", ICreatorRoyaltiesControl.RoyaltyConfiguration(0, 0, address(0)), admin, _emptyInitData());
    }

    function init(uint32 royaltySchedule, uint32 royaltyBps, address royaltyRecipient) internal {
        target.initialize(
            "test",
            "test",
            ICreatorRoyaltiesControl.RoyaltyConfiguration(royaltySchedule, royaltyBps, royaltyRecipient),
            admin,
            _emptyInitData()
        );
    }

    function test_packageJsonVersion() public {
        string memory package = vm.readFile("./package.json");
        assertEq(package.readString(".version"), target.contractVersion());
    }

    function test_initialize(uint32 royaltySchedule, uint32 royaltyBPS, address royaltyRecipient, address payable defaultAdmin) external {
        vm.assume(royaltySchedule != 1);
        vm.assume(royaltyRecipient != address(0) && royaltySchedule != 0 && royaltyBPS != 0);
        ICreatorRoyaltiesControl.RoyaltyConfiguration memory config = ICreatorRoyaltiesControl.RoyaltyConfiguration(
            royaltySchedule,
            royaltyBPS,
            royaltyRecipient
        );
        target.initialize("contract name", "test", config, defaultAdmin, _emptyInitData());

        assertEq(target.contractURI(), "test");
        assertEq(target.name(), "contract name");
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
        vm.assume(royaltyRecipient != address(0) && royaltySchedule != 0 && royaltyBPS != 0);
        ICreatorRoyaltiesControl.RoyaltyConfiguration memory config = ICreatorRoyaltiesControl.RoyaltyConfiguration(
            royaltySchedule,
            royaltyBPS,
            royaltyRecipient
        );
        bytes[] memory setupActions = new bytes[](1);
        setupActions[0] = abi.encodeWithSelector(IZoraCreator1155.setupNewToken.selector, "test", maxSupply);
        target.initialize("", "test", config, defaultAdmin, setupActions);

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
        vm.assume(royaltyRecipient != address(0) && royaltySchedule != 0 && royaltyBPS != 0);
        ICreatorRoyaltiesControl.RoyaltyConfiguration memory config = ICreatorRoyaltiesControl.RoyaltyConfiguration(
            royaltySchedule,
            royaltyBPS,
            royaltyRecipient
        );
        target.initialize("test", "test", config, defaultAdmin, _emptyInitData());

        vm.expectRevert();
        target.initialize("test", "test", config, defaultAdmin, _emptyInitData());
    }

    function test_contractVersion() external {
        init();

        string memory package = vm.readFile("./package.json");
        assertEq(package.readString(".version"), target.contractVersion());
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

    function test_setupNewToken_asMinter() external {
        init();

        address minterUser = address(0x999ab9);
        vm.startPrank(admin);
        target.addPermission(target.CONTRACT_BASE_ID(), minterUser, target.PERMISSION_BIT_MINTER());
        vm.stopPrank();

        vm.startPrank(minterUser);
        uint256 newToken = target.setupNewToken("test", 1);

        target.adminMint(minterUser, newToken, 1, "");
        assertEq(target.uri(1), "test");
    }

    function test_setupNewToken_revertOnlyAdminOrRole() external {
        init();

        vm.expectRevert(abi.encodeWithSelector(IZoraCreator1155Errors.UserMissingRoleForToken.selector, address(this), 0, target.PERMISSION_BIT_MINTER()));
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
        target.initialize("", "", ICreatorRoyaltiesControl.RoyaltyConfiguration(0, 0, address(0)), admin, _emptyInitData());

        SimpleRenderer contractRenderer = new SimpleRenderer();
        contractRenderer.setContractURI("contract renderer");
        SimpleRenderer singletonRenderer = new SimpleRenderer();

        vm.startPrank(admin);
        target.setTokenMetadataRenderer(0, contractRenderer);
        target.callRenderer(0, abi.encodeWithSelector(SimpleRenderer.setup.selector, "fallback renderer"));
        uint256 tokenId = target.setupNewToken("", 1);
        target.setTokenMetadataRenderer(tokenId, singletonRenderer);
        target.callRenderer(tokenId, abi.encodeWithSelector(SimpleRenderer.setup.selector, "singleton renderer"));
        vm.stopPrank();

        assertEq(address(target.getCustomRenderer(0)), address(contractRenderer));
        assertEq(target.contractURI(), "contract renderer");
        assertEq(address(target.getCustomRenderer(tokenId)), address(singletonRenderer));
        assertEq(target.uri(tokenId), "singleton renderer");

        vm.prank(admin);
        target.setTokenMetadataRenderer(tokenId, IRenderer1155(address(0)));
        assertEq(address(target.getCustomRenderer(tokenId)), address(contractRenderer));
        assertEq(target.uri(tokenId), "fallback renderer");
    }

    function test_setTokenMetadataRenderer_revertOnlyAdminOrRole() external {
        init();

        vm.expectRevert(abi.encodeWithSelector(IZoraCreator1155Errors.UserMissingRoleForToken.selector, address(this), 0, target.PERMISSION_BIT_METADATA()));
        target.setTokenMetadataRenderer(0, IRenderer1155(address(0)));
    }

    function test_addPermission(uint256 tokenId, uint256 permission, address user) external {
        vm.assume(permission != 0);
        init();

        vm.prank(admin);
        target.setupNewToken("test", 1000);

        vm.prank(admin);
        target.addPermission(tokenId, user, permission);

        assertEq(target.permissions(tokenId, user), permission);
    }

    function test_addPermission_revertOnlyAdminOrRole(uint256 tokenId) external {
        vm.assume(tokenId != 0);
        init();

        vm.expectRevert(abi.encodeWithSelector(IZoraCreator1155Errors.UserMissingRoleForToken.selector, recipient, tokenId, adminRole));
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

        assertEq(target.permissions(tokenId, user), 0);
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

        vm.expectRevert(abi.encodeWithSelector(IZoraCreator1155Errors.UserMissingRoleForToken.selector, recipient, tokenId, adminRole));
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

    function test_adminMintMinterRole(uint256 quantity) external {
        vm.assume(quantity < 1000);
        init();

        vm.prank(admin);
        uint256 tokenId = target.setupNewToken("test", 1000);

        vm.prank(admin);
        // 2 = permission bit minter
        target.addPermission(tokenId, address(0x394), 2);

        vm.prank(address(0x394));
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

        vm.expectRevert(
            abi.encodeWithSelector(IZoraCreator1155Errors.UserMissingRoleForToken.selector, address(this), tokenId, target.PERMISSION_BIT_MINTER())
        );
        target.adminMint(address(0), tokenId, 0, "");
    }

    function test_adminMint_revertMaxSupply(uint256 quantity) external {
        vm.assume(quantity > 0);
        init();

        vm.prank(admin);
        uint256 tokenId = target.setupNewToken("test", quantity - 1);

        vm.expectRevert(abi.encodeWithSelector(IZoraCreator1155Errors.CannotMintMoreTokens.selector, tokenId, quantity, 0, quantity - 1));
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

    function test_adminMintBatchWithHook(uint256 quantity1, uint256 quantity2) external {
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

        MockTransferHookReceiver testHook = new MockTransferHookReceiver();

        vm.prank(admin);
        target.setTransferHook(testHook);

        vm.prank(admin);
        target.adminMintBatch(recipient, tokenIds, quantities, "");

        IZoraCreator1155TypesV1.TokenData memory tokenData1 = target.getTokenInfo(tokenId1);
        IZoraCreator1155TypesV1.TokenData memory tokenData2 = target.getTokenInfo(tokenId2);

        assertEq(testHook.hasTransfer(tokenId1), true);
        assertEq(testHook.hasTransfer(tokenId2), true);
        assertEq(testHook.hasTransfer(1000), false);

        assertEq(tokenData1.totalMinted, quantity1);
        assertEq(tokenData2.totalMinted, quantity2);
        assertEq(target.balanceOf(recipient, tokenId1), quantity1);
        assertEq(target.balanceOf(recipient, tokenId2), quantity2);
    }

    function test_adminMintWithHook(uint256 quantity1) external {
        vm.assume(quantity1 < 1000);
        init();

        vm.prank(admin);
        uint256 tokenId1 = target.setupNewToken("test", 1000);

        MockTransferHookReceiver testHook = new MockTransferHookReceiver();

        vm.prank(admin);
        target.setTransferHook(testHook);

        vm.prank(admin);
        target.adminMint(recipient, tokenId1, quantity1, "");

        IZoraCreator1155TypesV1.TokenData memory tokenData1 = target.getTokenInfo(tokenId1);

        assertEq(testHook.hasTransfer(tokenId1), true);
        assertEq(testHook.hasTransfer(1000), false);

        assertEq(tokenData1.totalMinted, quantity1);
        assertEq(target.balanceOf(recipient, tokenId1), quantity1);
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

    function test_adminMintWithInvalidScheduleSkipsSchedule() external {
        // This configuration is invalid
        vm.expectRevert();
        target.initialize("", "test", ICreatorRoyaltiesControl.RoyaltyConfiguration(10, 0, address(0)), admin, _emptyInitData());
    }

    function test_adminMintWithEmptyScheduleSkipsSchedule() external {
        // every 0th token is sent so no tokens
        init(0, 0, address(0x99a));

        vm.prank(admin);
        uint256 tokenId1 = target.setupNewToken("test", 1000);

        uint256[] memory tokenIds = new uint256[](1);
        uint256[] memory quantities = new uint256[](1);
        tokenIds[0] = tokenId1;
        quantities[0] = 10;

        vm.prank(admin);
        target.adminMintBatch(recipient, tokenIds, quantities, "");

        assertEq(target.balanceOf(recipient, tokenId1), 10);
    }

    function test_adminMintBatch_revertOnlyAdminOrRole() external {
        init();

        vm.prank(admin);
        uint256 tokenId = target.setupNewToken("test", 1000);

        uint256[] memory tokenIds = new uint256[](1);
        uint256[] memory quantities = new uint256[](1);
        tokenIds[0] = tokenId;
        quantities[0] = 0;

        vm.expectRevert(
            abi.encodeWithSelector(IZoraCreator1155Errors.UserMissingRoleForToken.selector, address(this), tokenId, target.PERMISSION_BIT_MINTER())
        );
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

        vm.expectRevert(abi.encodeWithSelector(IZoraCreator1155Errors.CannotMintMoreTokens.selector, tokenId, quantity, 0, quantity - 1));
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
        vm.assume(quantity > 0 && quantity < type(uint200).max);

        init();

        vm.prank(admin);
        uint256 tokenId = target.setupNewToken("test", quantity);

        vm.prank(admin);
        target.addPermission(tokenId, address(simpleMinter), minterRole);

        uint256 totalReward = target.computeTotalReward(quantity);
        vm.deal(admin, totalReward);

        vm.prank(admin);
        target.mint{value: totalReward}(simpleMinter, tokenId, quantity, abi.encode(recipient));

        IZoraCreator1155TypesV1.TokenData memory tokenData = target.getTokenInfo(tokenId);
        assertEq(tokenData.totalMinted, quantity);
        assertEq(target.balanceOf(recipient, tokenId), quantity);
    }

    function test_mint_revertOnlyMinter() external {
        init();

        vm.prank(admin);
        uint256 tokenId = target.setupNewToken("test", 1000);

        vm.expectRevert(abi.encodeWithSelector(IZoraCreator1155Errors.UserMissingRoleForToken.selector, address(0), tokenId, target.PERMISSION_BIT_MINTER()));
        target.mint(SimpleMinter(payable(address(0))), tokenId, 0, "");
    }

    function test_mint_revertCannotMintMoreTokens() external {
        init();

        uint256 totalReward = target.computeTotalReward(1001);
        vm.deal(admin, totalReward);

        vm.startPrank(admin);

        uint256 tokenId = target.setupNewToken("test", 1000);

        target.addPermission(tokenId, address(simpleMinter), adminRole);

        vm.expectRevert(abi.encodeWithSelector(IZoraCreator1155Errors.CannotMintMoreTokens.selector, tokenId, 1001, 0, 1000));
        target.mint{value: totalReward}(simpleMinter, tokenId, 1001, abi.encode(recipient));

        vm.stopPrank();
    }

    function test_mintFee_returnsMintFee() public {
        assertEq(target.mintFee(), 0.000777 ether);
    }

    function test_FreeMintRewards(uint256 quantity) public {
        vm.assume(quantity > 0 && quantity < type(uint200).max);

        init();

        vm.prank(admin);
        uint256 tokenId = target.setupNewToken("test", quantity);

        vm.prank(admin);
        target.addPermission(tokenId, address(simpleMinter), adminRole);

        RewardsSettings memory settings = target.computeFreeMintRewards(quantity);

        uint256 totalReward = target.computeTotalReward(quantity);
        vm.deal(collector, totalReward);

        vm.prank(collector);
        target.mintWithRewards{value: totalReward}(simpleMinter, tokenId, quantity, abi.encode(recipient), address(0));

        (, , address fundsRecipient, , , ) = target.config();

        assertEq(protocolRewards.balanceOf(recipient), 0);
        assertEq(protocolRewards.balanceOf(fundsRecipient), settings.creatorReward + settings.firstMinterReward);
        assertEq(protocolRewards.balanceOf(zora), settings.zoraReward + settings.mintReferralReward + settings.createReferralReward);
    }

    function test_FreeMintRewardsWithCreateReferral(uint256 quantity) public {
        vm.assume(quantity > 0 && quantity < type(uint200).max);

        init();

        vm.prank(admin);
        uint256 tokenId = target.setupNewTokenWithCreateReferral("test", quantity, createReferral);

        vm.prank(admin);
        target.addPermission(tokenId, address(simpleMinter), adminRole);

        RewardsSettings memory settings = target.computeFreeMintRewards(quantity);

        uint256 totalReward = target.computeTotalReward(quantity);
        vm.deal(collector, totalReward);

        vm.prank(collector);
        target.mintWithRewards{value: totalReward}(simpleMinter, tokenId, quantity, abi.encode(recipient), address(0));

        (, , address fundsRecipient, , , ) = target.config();

        assertEq(protocolRewards.balanceOf(recipient), 0);
        assertEq(protocolRewards.balanceOf(fundsRecipient), settings.creatorReward + settings.firstMinterReward);
        assertEq(protocolRewards.balanceOf(createReferral), settings.createReferralReward);
        assertEq(protocolRewards.balanceOf(zora), settings.zoraReward + settings.mintReferralReward);
    }

    function test_FreeMintRewardsWithMintReferral(uint256 quantity) public {
        vm.assume(quantity > 0 && quantity < type(uint200).max);

        init();

        vm.prank(admin);
        uint256 tokenId = target.setupNewToken("test", quantity);

        vm.prank(admin);
        target.addPermission(tokenId, address(simpleMinter), adminRole);

        RewardsSettings memory settings = target.computeFreeMintRewards(quantity);

        uint256 totalReward = target.computeTotalReward(quantity);
        vm.deal(collector, totalReward);

        vm.prank(collector);
        target.mintWithRewards{value: totalReward}(simpleMinter, tokenId, quantity, abi.encode(recipient), mintReferral);

        (, , address fundsRecipient, , , ) = target.config();

        assertEq(protocolRewards.balanceOf(recipient), 0);
        assertEq(protocolRewards.balanceOf(fundsRecipient), settings.creatorReward + settings.firstMinterReward);
        assertEq(protocolRewards.balanceOf(mintReferral), settings.mintReferralReward);
        assertEq(protocolRewards.balanceOf(zora), settings.zoraReward + settings.createReferralReward);
    }

    function test_FreeMintRewardsWithCreateAndMintReferral(uint256 quantity) public {
        vm.assume(quantity > 0 && quantity < type(uint200).max);

        init();

        vm.prank(admin);
        uint256 tokenId = target.setupNewTokenWithCreateReferral("test", quantity, createReferral);

        vm.prank(admin);
        target.addPermission(tokenId, address(simpleMinter), adminRole);

        RewardsSettings memory settings = target.computeFreeMintRewards(quantity);

        uint256 totalReward = target.computeTotalReward(quantity);
        vm.deal(collector, totalReward);

        vm.prank(collector);
        target.mintWithRewards{value: totalReward}(simpleMinter, tokenId, quantity, abi.encode(recipient), mintReferral);

        (, , address fundsRecipient, , , ) = target.config();

        assertEq(protocolRewards.balanceOf(recipient), 0);
        assertEq(protocolRewards.balanceOf(fundsRecipient), settings.creatorReward + settings.firstMinterReward);
        assertEq(protocolRewards.balanceOf(createReferral), settings.createReferralReward);
        assertEq(protocolRewards.balanceOf(mintReferral), settings.mintReferralReward);
        assertEq(protocolRewards.balanceOf(zora), settings.zoraReward);
    }

    function testRevert_InsufficientEthForFreeMintRewards(uint256 quantity) public {
        vm.assume(quantity > 0 && quantity < type(uint200).max);

        init();

        vm.prank(admin);
        uint256 tokenId = target.setupNewToken("test", quantity);

        vm.prank(admin);
        target.addPermission(tokenId, address(simpleMinter), adminRole);

        vm.prank(collector);
        vm.expectRevert(abi.encodeWithSignature("INVALID_ETH_AMOUNT()"));
        target.mintWithRewards(simpleMinter, tokenId, quantity, abi.encode(recipient), address(0));
    }

    function test_PaidMintRewards(uint256 quantity, uint256 salePrice) public {
        vm.assume(quantity > 0 && quantity < 1_000_000);
        vm.assume(salePrice > 0 && salePrice < 10 ether);

        init();

        vm.startPrank(admin);

        uint256 tokenId = target.setupNewToken("test", quantity);
        target.addPermission(tokenId, address(fixedPriceMinter), adminRole);
        target.callSale(
            tokenId,
            fixedPriceMinter,
            abi.encodeWithSelector(
                ZoraCreatorFixedPriceSaleStrategy.setSale.selector,
                tokenId,
                ZoraCreatorFixedPriceSaleStrategy.SalesConfig({
                    pricePerToken: uint96(salePrice),
                    saleStart: 0,
                    saleEnd: type(uint64).max,
                    maxTokensPerAddress: 0,
                    fundsRecipient: address(0)
                })
            )
        );

        vm.stopPrank();

        RewardsSettings memory settings = target.computePaidMintRewards(quantity);

        uint256 totalReward = target.computeTotalReward(quantity);
        uint256 totalSale = quantity * salePrice;
        uint256 totalValue = totalReward + totalSale;

        vm.deal(collector, totalValue);

        vm.prank(collector);
        target.mintWithRewards{value: totalValue}(fixedPriceMinter, tokenId, quantity, abi.encode(recipient), address(0));

        assertEq(address(target).balance, totalSale);

        assertEq(protocolRewards.balanceOf(admin), settings.firstMinterReward);
        assertEq(protocolRewards.balanceOf(zora), settings.zoraReward + settings.mintReferralReward + settings.createReferralReward);
    }

    function test_PaidMintRewardsWithMintReferral(uint256 quantity, uint256 salePrice) public {
        vm.assume(quantity > 0 && quantity < 1_000_000);
        vm.assume(salePrice > 0 && salePrice < 10 ether);

        init();

        vm.startPrank(admin);

        uint256 tokenId = target.setupNewToken("test", quantity);
        target.addPermission(tokenId, address(fixedPriceMinter), adminRole);
        target.callSale(
            tokenId,
            fixedPriceMinter,
            abi.encodeWithSelector(
                ZoraCreatorFixedPriceSaleStrategy.setSale.selector,
                tokenId,
                ZoraCreatorFixedPriceSaleStrategy.SalesConfig({
                    pricePerToken: uint96(salePrice),
                    saleStart: 0,
                    saleEnd: type(uint64).max,
                    maxTokensPerAddress: 0,
                    fundsRecipient: address(0)
                })
            )
        );

        vm.stopPrank();

        RewardsSettings memory settings = target.computePaidMintRewards(quantity);

        uint256 totalReward = target.computeTotalReward(quantity);
        uint256 totalSale = quantity * salePrice;
        uint256 totalValue = totalReward + totalSale;

        vm.deal(collector, totalValue);

        vm.prank(collector);
        target.mintWithRewards{value: totalValue}(fixedPriceMinter, tokenId, quantity, abi.encode(recipient), mintReferral);

        assertEq(address(target).balance, totalSale);

        assertEq(protocolRewards.balanceOf(mintReferral), settings.mintReferralReward);
        assertEq(protocolRewards.balanceOf(admin), settings.firstMinterReward);
        assertEq(protocolRewards.balanceOf(zora), settings.zoraReward + settings.createReferralReward);
    }

    function test_PaidMintRewardsWithCreateReferral(uint256 quantity, uint256 salePrice) public {
        vm.assume(quantity > 0 && quantity < 1_000_000);
        vm.assume(salePrice > 0 && salePrice < 10 ether);

        init();

        vm.startPrank(admin);
        uint256 tokenId = target.setupNewTokenWithCreateReferral("test", quantity, createReferral);

        target.addPermission(tokenId, address(fixedPriceMinter), adminRole);
        target.callSale(
            tokenId,
            fixedPriceMinter,
            abi.encodeWithSelector(
                ZoraCreatorFixedPriceSaleStrategy.setSale.selector,
                tokenId,
                ZoraCreatorFixedPriceSaleStrategy.SalesConfig({
                    pricePerToken: uint96(salePrice),
                    saleStart: 0,
                    saleEnd: type(uint64).max,
                    maxTokensPerAddress: 0,
                    fundsRecipient: address(0)
                })
            )
        );

        vm.stopPrank();

        RewardsSettings memory settings = target.computePaidMintRewards(quantity);

        uint256 totalReward = target.computeTotalReward(quantity);
        uint256 totalSale = quantity * salePrice;
        uint256 totalValue = totalReward + totalSale;

        vm.deal(collector, totalValue);

        vm.prank(collector);
        target.mintWithRewards{value: totalValue}(fixedPriceMinter, tokenId, quantity, abi.encode(recipient), address(0));

        assertEq(address(target).balance, totalSale);
        assertEq(protocolRewards.balanceOf(admin), settings.firstMinterReward);
        assertEq(protocolRewards.balanceOf(createReferral), settings.createReferralReward);
        assertEq(protocolRewards.balanceOf(zora), settings.zoraReward + settings.mintReferralReward);
    }

    function test_PaidMintRewardsWithCreateAndMintReferral(uint256 quantity, uint256 salePrice) public {
        vm.assume(quantity > 0 && quantity < 1_000_000);
        vm.assume(salePrice > 0 && salePrice < 10 ether);

        init();

        vm.startPrank(admin);

        uint256 tokenId = target.setupNewTokenWithCreateReferral("test", quantity, createReferral);
        target.addPermission(tokenId, address(fixedPriceMinter), adminRole);
        target.callSale(
            tokenId,
            fixedPriceMinter,
            abi.encodeWithSelector(
                ZoraCreatorFixedPriceSaleStrategy.setSale.selector,
                tokenId,
                ZoraCreatorFixedPriceSaleStrategy.SalesConfig({
                    pricePerToken: uint96(salePrice),
                    saleStart: 0,
                    saleEnd: type(uint64).max,
                    maxTokensPerAddress: 0,
                    fundsRecipient: address(0)
                })
            )
        );

        vm.stopPrank();

        RewardsSettings memory settings = target.computePaidMintRewards(quantity);

        uint256 totalReward = target.computeTotalReward(quantity);
        uint256 totalSale = quantity * salePrice;
        uint256 totalValue = totalReward + totalSale;

        vm.deal(collector, totalValue);

        vm.prank(collector);
        target.mintWithRewards{value: totalValue}(fixedPriceMinter, tokenId, quantity, abi.encode(recipient), mintReferral);

        assertEq(address(target).balance, totalSale);
        assertEq(protocolRewards.balanceOf(admin), settings.firstMinterReward);
        assertEq(protocolRewards.balanceOf(mintReferral), settings.mintReferralReward);
        assertEq(protocolRewards.balanceOf(createReferral), settings.createReferralReward);
        assertEq(protocolRewards.balanceOf(zora), settings.zoraReward);
    }

    function testRevert_InsufficientEthForPaidMintRewards(uint256 quantity, uint256 salePrice) public {
        vm.assume(quantity > 0 && quantity < 1_000_000);
        vm.assume(salePrice > 0 && salePrice < 10 ether);

        init();

        vm.startPrank(admin);

        uint256 tokenId = target.setupNewToken("test", quantity);
        target.addPermission(tokenId, address(fixedPriceMinter), adminRole);
        target.callSale(
            tokenId,
            fixedPriceMinter,
            abi.encodeWithSelector(
                ZoraCreatorFixedPriceSaleStrategy.setSale.selector,
                tokenId,
                ZoraCreatorFixedPriceSaleStrategy.SalesConfig({
                    pricePerToken: uint96(salePrice),
                    saleStart: 0,
                    saleEnd: type(uint64).max,
                    maxTokensPerAddress: 0,
                    fundsRecipient: address(0)
                })
            )
        );

        vm.stopPrank();

        vm.prank(collector);
        vm.expectRevert(abi.encodeWithSignature("INVALID_ETH_AMOUNT()"));
        target.mintWithRewards(fixedPriceMinter, tokenId, quantity, abi.encode(recipient), address(0));
    }

    function test_FirstMinterRewardReceivedOnConsecutiveMints(uint32 quantity) public {
        vm.assume(quantity > 0 && quantity < type(uint200).max);

        init();

        PremintConfig memory premintConfig = PremintConfig({
            tokenConfig: TokenCreationConfig({
                // Metadata URI for the created token
                tokenURI: "",
                // Max supply of the created token
                maxSupply: type(uint64).max,
                // Max tokens that can be minted for an address, 0 if unlimited
                maxTokensPerAddress: type(uint64).max,
                // Price per token in eth wei. 0 for a free mint.
                pricePerToken: 0,
                // The start time of the mint, 0 for immediate.  Prevents signatures from being used until the start time.
                mintStart: 0,
                // The duration of the mint, starting from the first mint of this token. 0 for infinite
                mintDuration: type(uint64).max - 1,
                // RoyaltyMintSchedule for created tokens. Every nth token will go to the royalty recipient.
                royaltyMintSchedule: 0,
                // RoyaltyBPS for created tokens. The royalty amount in basis points for secondary sales.
                royaltyBPS: 0,
                // RoyaltyRecipient for created tokens. The address that will receive the royalty payments.
                royaltyRecipient: address(0),
                // Fixed price minter address
                fixedPriceMinter: address(fixedPriceMinter)
            }),
            // Unique id of the token, used to ensure that multiple signatures can't be used to create the same intended token.
            // only one signature per token id, scoped to the contract hash can be executed.
            uid: 1,
            // Version of this premint, scoped to the uid and contract.  Not used for logic in the contract, but used externally to track the newest version
            version: 1,
            // If executing this signature results in preventing any signature with this uid from being minted.
            deleted: false
        });

        address[] memory collectors = new address[](3);
        collectors[0] = makeAddr("firstMinter");
        collectors[1] = makeAddr("collector1");
        collectors[2] = makeAddr("collector2");

        uint256 chainId;
        assembly {
            chainId := chainid()
        }

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(adminKey, ZoraCreator1155Attribution.premintHashedTypeDataV4(premintConfig, address(target), chainId));

        bytes memory signature = abi.encodePacked(r, s, v);

        vm.prank(collector);
        uint256 tokenId = target.delegateSetupNewToken(premintConfig, signature, collectors[0]);

        RewardsSettings memory settings = target.computeFreeMintRewards(quantity);

        uint256 totalReward = target.computeTotalReward(quantity);
        vm.deal(collectors[1], totalReward);
        vm.prank(collectors[1]);
        target.mintWithRewards{value: totalReward}(fixedPriceMinter, tokenId, quantity, abi.encode(collectors[1]), address(0));

        assertEq(protocolRewards.balanceOf(collectors[0]), settings.firstMinterReward);

        vm.deal(collectors[2], totalReward);

        vm.prank(collectors[2]);
        target.mintWithRewards{value: totalReward}(fixedPriceMinter, tokenId, quantity, abi.encode(collectors[2]), address(0));

        assertEq(protocolRewards.balanceOf(collectors[0]), settings.firstMinterReward * 2);
    }

    function test_AssumeFirstMinterRecipientIsAddress(uint256 quantity) public {
        vm.assume(quantity > 0 && quantity < type(uint200).max);

        init();

        vm.prank(admin);
        uint256 tokenId = target.setupNewToken("test", quantity);

        vm.prank(admin);
        target.addPermission(tokenId, address(simpleMinter), adminRole);

        RewardsSettings memory settings = target.computeFreeMintRewards(quantity);

        uint256 totalReward = target.computeTotalReward(quantity);
        vm.deal(collector, totalReward);

        uint256 mintRecipient = 1234;

        address rewardRecipient = makeAddr("rewardRecipient");

        vm.prank(collector);
        target.mintWithRewards{value: totalReward}(simpleMinter, tokenId, quantity, abi.encode(mintRecipient), rewardRecipient);

        (, , address fundsRecipient, , , ) = target.config();

        assertEq(protocolRewards.balanceOf(address(uint160(mintRecipient))), 0);
        assertEq(protocolRewards.balanceOf(rewardRecipient), settings.mintReferralReward);
        assertEq(protocolRewards.balanceOf(fundsRecipient), settings.creatorReward + settings.firstMinterReward);
        assertEq(protocolRewards.balanceOf(zora), settings.zoraReward + settings.createReferralReward);
    }

    function testRevert_WrongValueForSale(uint256 quantity, uint256 salePrice) public {
        vm.assume(quantity > 0 && quantity < 1_000_000);
        vm.assume(salePrice > 0 && salePrice < 10 ether);

        init();

        vm.startPrank(admin);

        uint256 tokenId = target.setupNewToken("test", quantity);
        target.addPermission(tokenId, address(fixedPriceMinter), adminRole);
        target.callSale(
            tokenId,
            fixedPriceMinter,
            abi.encodeWithSelector(
                ZoraCreatorFixedPriceSaleStrategy.setSale.selector,
                tokenId,
                ZoraCreatorFixedPriceSaleStrategy.SalesConfig({
                    pricePerToken: uint96(salePrice),
                    saleStart: 0,
                    saleEnd: type(uint64).max,
                    maxTokensPerAddress: 0,
                    fundsRecipient: address(0)
                })
            )
        );

        vm.stopPrank();

        uint256 totalReward = target.computeTotalReward(quantity);

        vm.expectRevert(abi.encodeWithSignature("WrongValueSent()"));
        target.mintWithRewards{value: totalReward}(fixedPriceMinter, tokenId, quantity, abi.encode(recipient), address(0));
    }

    function test_callSale() external {
        init();

        vm.startPrank(admin);

        uint256 tokenId = target.setupNewToken("", 1);
        target.addPermission(tokenId, address(simpleMinter), minterRole);

        target.callSale(tokenId, simpleMinter, abi.encodeWithSignature("setNum(uint256)", 1));
        assertEq(simpleMinter.num(), 1);

        vm.expectRevert(abi.encodeWithSignature("Call_TokenIdMismatch()"));
        target.callSale(tokenId, simpleMinter, abi.encodeWithSignature("setNum(uint256)", 0));

        vm.stopPrank();
    }

    function test_callRenderer() external {
        init();

        SimpleRenderer renderer = new SimpleRenderer();

        vm.startPrank(admin);

        uint256 tokenId = target.setupNewToken("", 1);
        target.setTokenMetadataRenderer(tokenId, renderer);
        assertEq(target.uri(tokenId), "");
        target.callRenderer(tokenId, abi.encodeWithSelector(SimpleRenderer.setup.selector, "renderer"));
        assertEq(target.uri(tokenId), "renderer");

        target.callRenderer(tokenId, abi.encodeWithSelector(SimpleRenderer.setup.selector, "callRender successful"));
        assertEq(target.uri(tokenId), "callRender successful");

        vm.expectRevert(abi.encodeWithSelector(IZoraCreator1155Errors.CallFailed.selector, ""));
        target.callRenderer(tokenId, abi.encodeWithSelector(SimpleRenderer.setup.selector, ""));

        vm.stopPrank();
    }

    function test_UpdateContractMetadataFailsContract() external {
        init();

        vm.expectRevert();
        vm.prank(admin);
        target.updateTokenURI(0, "test");
    }

    function test_ContractNameUpdate() external {
        init();
        assertEq(target.name(), "test");

        vm.prank(admin);
        target.updateContractMetadata("newURI", "ASDF");
        assertEq(target.name(), "ASDF");
    }

    function test_noSymbol() external {
        assertEq(target.symbol(), "");
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
        target.setTokenMetadataRenderer(tokenId, renderer);
    }

    function test_callRendererFails() external {
        init();

        SimpleRenderer renderer = new SimpleRenderer();

        vm.startPrank(admin);
        uint256 tokenId = target.setupNewToken("", 1);
        target.setTokenMetadataRenderer(tokenId, renderer);

        vm.expectRevert(abi.encodeWithSelector(IZoraCreator1155Errors.CallFailed.selector, ""));
        target.callRenderer(tokenId, "0xfoobar");
    }

    function test_supportsInterface() external {
        init();

        // TODO: make this static
        bytes4 interfaceId = type(IZoraCreator1155).interfaceId;
        assertEq(target.supportsInterface(interfaceId), true);

        bytes4 erc1155InterfaceId = bytes4(0xd9b67a26);
        assertTrue(target.supportsInterface(erc1155InterfaceId));

        bytes4 erc165InterfaceId = bytes4(0x01ffc9a7);
        assertTrue(target.supportsInterface(erc165InterfaceId));

        bytes4 erc2981InterfaceId = bytes4(0x2a55205a);
        assertTrue(target.supportsInterface(erc2981InterfaceId));
    }

    function test_burnBatch() external {
        init();

        vm.prank(admin);
        uint256 tokenId = target.setupNewToken("test", 10);

        vm.prank(admin);
        target.addPermission(tokenId, address(simpleMinter), adminRole);

        uint256 totalReward = target.computeTotalReward(5);
        vm.deal(admin, totalReward);

        vm.prank(admin);
        target.mint{value: totalReward}(simpleMinter, tokenId, 5, abi.encode(recipient));

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

        vm.prank(admin);
        target.addPermission(tokenId, address(simpleMinter), adminRole);

        uint256 totalReward = target.computeTotalReward(5);
        vm.deal(admin, totalReward);

        vm.prank(admin);
        target.mint{value: totalReward}(simpleMinter, tokenId, 5, abi.encode(recipient));

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

        vm.prank(admin);
        target.addPermission(tokenId, address(simpleMinter), minterRole);

        uint256 totalReward = target.computeTotalReward(1000);
        uint256 totalSale = 1 ether;
        uint256 totalValue = totalReward + totalSale;

        vm.deal(admin, totalValue);

        vm.prank(admin);
        target.mint{value: totalValue}(simpleMinter, tokenId, 1000, abi.encode(recipient));

        vm.prank(admin);
        target.withdraw();

        assertEq(admin.balance, 1 ether);
    }

    function test_withdrawAll_revertETHWithdrawFailed() external {
        init();

        vm.prank(admin);
        uint256 tokenId = target.setupNewToken("test", 1000);

        SimpleMinter(payable(simpleMinter)).setReceiveETH(false);

        vm.prank(admin);
        target.setFundsRecipient(payable(simpleMinter));

        vm.prank(admin);
        target.addPermission(tokenId, address(simpleMinter), minterRole);

        vm.prank(admin);
        target.addPermission(0, address(simpleMinter), fundsManagerRole);

        uint256 totalReward = target.computeTotalReward(1000);
        uint256 totalSale = 1 ether;
        uint256 totalValue = totalReward + totalSale;

        vm.deal(admin, totalValue);
        vm.prank(admin);
        target.mint{value: totalValue}(simpleMinter, tokenId, 1000, abi.encode(recipient));

        vm.expectRevert(abi.encodeWithSelector(IZoraCreator1155Errors.ETHWithdrawFailed.selector, simpleMinter, 1 ether));
        vm.prank(address(simpleMinter));
        target.withdraw();
    }

    function test_unauthorizedUpgradeFails() external {
        address new1155Impl = address(new ZoraCreator1155Impl(zora, address(0), address(protocolRewards)));

        vm.expectRevert();
        target.upgradeTo(new1155Impl);
    }

    function test_authorizedUpgrade() external {
        init();
        address[] memory oldImpls = new address[](1);

        oldImpls[0] = address(zoraCreator1155Impl);

        address new1155Impl = address(new ZoraCreator1155Impl(zora, address(0), address(protocolRewards)));

        vm.prank(upgradeGate.owner());
        upgradeGate.registerUpgradePath(oldImpls, new1155Impl);

        vm.prank(admin);
        target.upgradeTo(new1155Impl);

        vm.prank(admin);
        uint256 tokenId = target.setupNewToken("test", 1000);

        vm.prank(admin);
        target.adminMint(address(0x1234), tokenId, 1, "");
    }

    function test_SupplyRoyaltyScheduleCannotBeOne() external {
        init();

        vm.prank(admin);
        uint256 tokenId = target.setupNewToken("test", 100);

        SimpleMinter minter = new SimpleMinter();
        vm.prank(admin);
        target.addPermission(tokenId, address(minter), adminRole);

        vm.prank(admin);
        vm.expectRevert(ICreatorRoyaltiesControl.InvalidMintSchedule.selector);
        target.updateRoyaltiesForToken(
            tokenId,
            ICreatorRoyaltiesControl.RoyaltyConfiguration({royaltyMintSchedule: 1, royaltyBPS: 0, royaltyRecipient: admin})
        );
    }

    function test_SupplyRoyaltyMint(uint32 royaltyMintSchedule, uint32 editionSize, uint256 mintQuantity) external {
        vm.assume(royaltyMintSchedule > 1 && royaltyMintSchedule <= editionSize && editionSize <= 100000 && mintQuantity > 0 && mintQuantity <= editionSize);
        uint256 totalRoyaltyMintsForSale = editionSize / royaltyMintSchedule;
        vm.assume(mintQuantity <= editionSize - totalRoyaltyMintsForSale);

        init();

        vm.prank(admin);
        uint256 tokenId = target.setupNewToken("test", editionSize);

        SimpleMinter minter = new SimpleMinter();
        vm.prank(admin);
        target.addPermission(tokenId, address(minter), adminRole);

        vm.startPrank(admin);
        target.updateRoyaltiesForToken(
            tokenId,
            ICreatorRoyaltiesControl.RoyaltyConfiguration({royaltyMintSchedule: royaltyMintSchedule, royaltyBPS: 0, royaltyRecipient: admin})
        );

        uint256 totalReward = target.computeTotalReward(mintQuantity);
        vm.deal(admin, totalReward);

        target.mint{value: totalReward}(minter, tokenId, mintQuantity, abi.encode(recipient));

        uint256 totalRoyaltyMintsForPurchase = mintQuantity / (royaltyMintSchedule - 1);
        totalRoyaltyMintsForPurchase = MathUpgradeable.min(totalRoyaltyMintsForPurchase, editionSize - mintQuantity);

        assertEq(target.balanceOf(recipient, tokenId), mintQuantity);
        assertEq(target.balanceOf(admin, tokenId), totalRoyaltyMintsForPurchase);

        vm.stopPrank();
    }

    function test_SupplyRoyaltyMintCleanNumbers() external {
        init();

        vm.prank(admin);
        uint256 tokenId = target.setupNewToken("test", 100);

        SimpleMinter minter = new SimpleMinter();
        vm.prank(admin);
        target.addPermission(tokenId, address(minter), adminRole);

        uint256 totalReward = target.computeTotalReward(80);
        vm.deal(admin, totalReward);

        vm.startPrank(admin);
        target.updateRoyaltiesForToken(
            tokenId,
            ICreatorRoyaltiesControl.RoyaltyConfiguration({royaltyMintSchedule: 5, royaltyBPS: 0, royaltyRecipient: admin})
        );
        target.mint{value: totalReward}(minter, tokenId, 80, abi.encode(recipient));

        assertEq(target.balanceOf(recipient, tokenId), 80);
        assertEq(target.balanceOf(admin, tokenId), 20);

        vm.stopPrank();
    }

    function test_SupplyRoyaltyMintEdgeCaseNumbers() external {
        init();

        vm.prank(admin);
        uint256 tokenId = target.setupNewToken("test", 137);

        SimpleMinter minter = new SimpleMinter();
        vm.prank(admin);
        target.addPermission(tokenId, address(minter), adminRole);

        uint256 totalReward = target.computeTotalReward(92);
        vm.deal(admin, totalReward);

        vm.startPrank(admin);
        target.updateRoyaltiesForToken(
            tokenId,
            ICreatorRoyaltiesControl.RoyaltyConfiguration({royaltyMintSchedule: 3, royaltyBPS: 0, royaltyRecipient: admin})
        );

        target.mint{value: totalReward}(minter, tokenId, 92, abi.encode(recipient));

        assertEq(target.balanceOf(recipient, tokenId), 92);
        assertEq(target.balanceOf(admin, tokenId), 45);

        vm.stopPrank();
    }

    function test_SupplyRoyaltyMintEdgeCaseNumbersOpenEdition() external {
        init();

        vm.prank(admin);
        uint256 tokenId = target.setupNewToken("test", type(uint256).max);

        SimpleMinter minter = new SimpleMinter();
        vm.prank(admin);
        target.addPermission(tokenId, address(minter), adminRole);

        uint256 totalReward = target.computeTotalReward(92);
        vm.deal(admin, totalReward);

        vm.startPrank(admin);
        target.updateRoyaltiesForToken(
            tokenId,
            ICreatorRoyaltiesControl.RoyaltyConfiguration({royaltyMintSchedule: 3, royaltyBPS: 0, royaltyRecipient: admin})
        );

        target.mint{value: totalReward}(minter, tokenId, 92, abi.encode(recipient));

        assertEq(target.balanceOf(recipient, tokenId), 92);
        assertEq(target.balanceOf(admin, tokenId), 46);

        vm.deal(admin, 0.000777 ether);

        target.mint{value: 0.000777 ether}(minter, tokenId, 1, abi.encode(recipient));

        assertEq(target.balanceOf(recipient, tokenId), 93);
        assertEq(target.balanceOf(admin, tokenId), 46);

        vm.stopPrank();
    }
}
