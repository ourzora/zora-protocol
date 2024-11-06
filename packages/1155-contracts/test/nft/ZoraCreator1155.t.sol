// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import {ProtocolRewards} from "@zoralabs/protocol-rewards/src/ProtocolRewards.sol";
import {IRewardSplits} from "@zoralabs/protocol-rewards/src/interfaces/IRewardSplits.sol";
import {RewardSplitsLib} from "@zoralabs/protocol-rewards/src/abstract/RewardSplits.sol";
import {MathUpgradeable} from "@zoralabs/openzeppelin-contracts-upgradeable/contracts/utils/math/MathUpgradeable.sol";
import {ZoraCreator1155Impl} from "../../src/nft/ZoraCreator1155Impl.sol";
import {ITransferHookReceiver} from "../../src/interfaces/ITransferHookReceiver.sol";
import {IReduceSupply} from "@zoralabs/shared-contracts/interfaces/IReduceSupply.sol";
import {Zora1155} from "../../src/proxies/Zora1155.sol";
import {ZoraCreatorFixedPriceSaleStrategy} from "../../src/minters/fixed-price/ZoraCreatorFixedPriceSaleStrategy.sol";
import {UpgradeGate} from "../../src/upgrades/UpgradeGate.sol";
import {PremintConfigV2, TokenCreationConfigV2} from "../../src/delegation/ZoraCreator1155Attribution.sol";
import {ZoraCreator1155Attribution} from "../../src/delegation/ZoraCreator1155Attribution.sol";
import {PremintEncoding} from "@zoralabs/shared-contracts/premint/PremintEncoding.sol";
import {IHasContractName} from "../../src/interfaces/IContractMetadata.sol";

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

    function onTokenTransferBatch(address, address, address, address, uint256[] memory ids, uint256[] memory, bytes memory) external {
        for (uint256 i = 0; i < ids.length; i++) {
            hasTransfer[ids[i]] = true;
        }
    }

    function onTokenTransfer(address, address, address, address, uint256 id, uint256, bytes memory) external {
        hasTransfer[id] = true;
    }

    function supportsInterface(bytes4 testInterface) external pure override returns (bool) {
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
    address internal timedSaleStrategy;
    address internal zora;
    address[] internal rewardsRecipients;
    address[] internal defaultRewardsRecipients;

    event ContractURIUpdated();
    event Purchased(address indexed sender, address indexed minter, uint256 indexed tokenId, uint256 quantity, uint256 value);
    event RewardsDeposit(
        address indexed creator,
        address indexed createReferral,
        address indexed mintReferral,
        address firstMinter,
        address zora,
        address from,
        uint256 creatorReward,
        uint256 createReferralReward,
        uint256 mintReferralReward,
        uint256 firstMinterReward,
        uint256 zoraReward
    );
    event UpdatedPermissions(uint256 indexed tokenId, address indexed user, uint256 indexed tokenPermissions);

    function setUp() external {
        creator = makeAddr("creator");
        collector = makeAddr("collector");
        mintReferral = makeAddr("mintReferral");
        createReferral = makeAddr("createReferral");
        zora = makeAddr("zora");
        timedSaleStrategy = makeAddr("timedSaleStrategy");

        rewardsRecipients = new address[](1);
        rewardsRecipients[0] = mintReferral;
        defaultRewardsRecipients = new address[](1);

        address adminAddress;
        (adminAddress, adminKey) = makeAddrAndKey("admin");
        admin = payable(adminAddress);
        recipient = vm.addr(0x2);

        protocolRewards = new ProtocolRewards();
        upgradeGate = new UpgradeGate();
        upgradeGate.initialize(admin);
        simpleMinter = new SimpleMinter();
        fixedPriceMinter = new ZoraCreatorFixedPriceSaleStrategy();

        zoraCreator1155Impl = new ZoraCreator1155Impl(zora, address(upgradeGate), address(protocolRewards), address(simpleMinter));
        target = ZoraCreator1155Impl(payable(address(new Zora1155(address(zoraCreator1155Impl)))));

        adminRole = target.PERMISSION_BIT_ADMIN();
        minterRole = target.PERMISSION_BIT_MINTER();
        fundsManagerRole = target.PERMISSION_BIT_FUNDS_MANAGER();
        metadataRole = target.PERMISSION_BIT_METADATA();
    }

    function computeTotalReward(uint256 totalReward, uint256 quantity) internal pure returns (uint256) {
        return totalReward * quantity;
    }

    function computeFreeMintRewards(uint256 totalValue) internal pure returns (IRewardSplits.RewardsSettings memory) {
        return RewardSplitsLib.getRewards(false, totalValue);
    }

    function computePaidMintRewards(uint256 totalValue) internal pure returns (IRewardSplits.RewardsSettings memory) {
        return RewardSplitsLib.getRewards(true, totalValue);
    }

    function _emptyInitData() internal pure returns (bytes[] memory response) {
        response = new bytes[](0);
    }

    function init() internal {
        target.initialize("test", "test", ICreatorRoyaltiesControl.RoyaltyConfiguration(0, 0, address(0)), admin, _emptyInitData());
    }

    function init(uint32 royaltyBps, address royaltyRecipient) internal {
        target.initialize("test", "test", ICreatorRoyaltiesControl.RoyaltyConfiguration(0, royaltyBps, royaltyRecipient), admin, _emptyInitData());
    }

    function setupNewTokenWithSimpleMinter(uint256 quantity) private returns (uint256) {
        vm.prank(admin);
        uint256 tokenId = target.setupNewToken("test", quantity);
        vm.prank(admin);
        target.addPermission(tokenId, address(simpleMinter), adminRole);
        vm.stopPrank();

        return tokenId;
    }

    function test_packageJsonVersion() public {
        string memory package = vm.readFile("./package.json");
        assertEq(package.readString(".version"), target.contractVersion());
    }

    function test_initialize(uint32 royaltyBPS, address royaltyRecipient, address payable defaultAdmin) external {
        vm.assume(royaltyRecipient != address(0) && royaltyBPS != 0);
        ICreatorRoyaltiesControl.RoyaltyConfiguration memory config = ICreatorRoyaltiesControl.RoyaltyConfiguration(0, royaltyBPS, royaltyRecipient);
        target.initialize("contract name", "test", config, defaultAdmin, _emptyInitData());

        assertEq(target.contractURI(), "test");
        assertEq(target.name(), "contract name");
        (, uint256 fetchedBps, address fetchedRecipient) = target.royalties(0);
        assertEq(fetchedBps, royaltyBPS);
        assertEq(fetchedRecipient, royaltyRecipient);
    }

    function test_initialize_withSetupActions(uint32 royaltyBPS, address royaltyRecipient, address payable defaultAdmin, uint256 maxSupply) external {
        vm.assume(royaltyRecipient != address(0) && royaltyBPS != 0);
        ICreatorRoyaltiesControl.RoyaltyConfiguration memory config = ICreatorRoyaltiesControl.RoyaltyConfiguration(0, royaltyBPS, royaltyRecipient);
        bytes[] memory setupActions = new bytes[](1);
        setupActions[0] = abi.encodeWithSelector(IZoraCreator1155.setupNewToken.selector, "test", maxSupply);
        target.initialize("", "test", config, defaultAdmin, setupActions);

        IZoraCreator1155TypesV1.TokenData memory tokenData = target.getTokenInfo(1);
        assertEq(tokenData.maxSupply, maxSupply);
    }

    function test_initialize_revertAlreadyInitialized(uint32 royaltyBPS, address royaltyRecipient, address payable defaultAdmin) external {
        vm.assume(royaltyRecipient != address(0) && royaltyBPS != 0);
        ICreatorRoyaltiesControl.RoyaltyConfiguration memory config = ICreatorRoyaltiesControl.RoyaltyConfiguration(0, royaltyBPS, royaltyRecipient);
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

    function test_removePermissionAdmin(uint256 tokenId, uint256 permission, address user) external {
        vm.assume(permission != 0);
        init();

        vm.prank(admin);
        target.addPermission(tokenId, user, permission);

        vm.prank(admin);
        target.removePermission(tokenId, user, permission);

        assertEq(target.permissions(tokenId, user), 0);
    }

    function test_removePermissionUser() external {
        init();

        address targetUser = address(0x240);

        vm.prank(admin);
        target.addPermission(0, targetUser, 2 ** 3);

        vm.prank(targetUser);
        target.removePermission(0, targetUser, 2 ** 3);

        assertEq(target.permissions(0, targetUser), 0);
    }

    function test_removePermissionsUser() external {
        init();

        address targetUser = address(0x240);

        vm.prank(admin);
        target.addPermission(0, targetUser, 2 ** 3 + 2 ** 4 + 2 ** 5);

        vm.prank(targetUser);
        target.removePermission(0, targetUser, 2 ** 3 + 2 ** 4);

        assertEq(target.permissions(0, targetUser), 2 ** 5);
    }

    function test_removePermissionSingleToken() external {
        init();

        address targetUser = address(0x025);

        vm.prank(admin);
        target.addPermission(10, targetUser, 2 ** 3);

        vm.prank(targetUser);
        vm.expectEmit();
        emit UpdatedPermissions(10, targetUser, 0);
        target.removePermission(10, targetUser, 2 ** 3);

        assertEq(target.permissions(10, targetUser), 0);
    }

    function test_removePermissionsUserNotAllowed() external {
        init();

        address targetUser = address(0x240);
        address userWithPermissions = address(0x14028);

        // Permissions granted that do _not_ include 2**1 (admin permission)
        uint256 permissions = 2 ** 3 + 2 ** 4 + 2 ** 5;

        vm.prank(admin);
        target.addPermission(0, userWithPermissions, permissions);

        uint256 adminPermissionBit = target.PERMISSION_BIT_ADMIN();

        vm.prank(targetUser);
        vm.expectRevert(abi.encodeWithSelector(IZoraCreator1155Errors.UserMissingRoleForToken.selector, targetUser, 0, adminPermissionBit));
        target.removePermission(0, userWithPermissions, permissions);

        assertEq(target.permissions(0, userWithPermissions), permissions);

        // Try again now from the user with permissions
        vm.prank(userWithPermissions);
        target.removePermission(0, userWithPermissions, permissions);

        assertEq(target.permissions(0, userWithPermissions), 0);
    }

    function test_removePermissionsUserAdmin() external {
        init();

        address targetUser = address(0x2401);

        uint256 permissions = 2 ** 3 + 2 ** 4 + 2 ** 6;

        vm.prank(admin);
        target.addPermission(0, targetUser, permissions);

        assertEq(target.permissions(0, targetUser), permissions);

        vm.expectEmit();
        emit UpdatedPermissions(0, targetUser, 2 ** 6);
        vm.prank(admin);
        target.removePermission(0, targetUser, 2 ** 3 + 2 ** 4);

        assertEq(target.permissions(0, targetUser), 2 ** 6);
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

        init(0, royaltyRecipient);

        vm.prank(admin);
        uint256 tokenId = target.setupNewToken("test", quantity);

        vm.prank(admin);
        target.adminMint(recipient, tokenId, quantity, "");

        IZoraCreator1155TypesV1.TokenData memory tokenData = target.getTokenInfo(tokenId);
        assertEq(tokenData.totalMinted, quantity);
        assertEq(target.balanceOf(recipient, tokenId), quantity);
    }

    function test_adminMintWithSchedule() external {
        uint256 quantity = 1000;
        address royaltyRecipient = address(0x3334);

        init(0, royaltyRecipient);

        vm.prank(admin);
        uint256 tokenId = target.setupNewToken("test", 1000);

        vm.prank(admin);
        target.adminMint(recipient, tokenId, quantity, "");

        IZoraCreator1155TypesV1.TokenData memory tokenData = target.getTokenInfo(tokenId);
        assertEq(tokenData.totalMinted, 1000);
        assertEq(target.balanceOf(recipient, tokenId), quantity);
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

    function test_adminMintWithInvalidScheduleSkipsSchedule(uint32 supplyRoyaltySchedule) external {
        vm.assume(supplyRoyaltySchedule != 0);

        address supplyRoyaltyRecipient = makeAddr("supplyRoyaltyRecipient");

        target.initialize("", "test", ICreatorRoyaltiesControl.RoyaltyConfiguration(supplyRoyaltySchedule, 0, supplyRoyaltyRecipient), admin, _emptyInitData());

        ICreatorRoyaltiesControl.RoyaltyConfiguration memory storedConfig = target.getRoyalties(0);

        assertEq(storedConfig.royaltyMintSchedule, 0);
    }

    function test_mint(uint256 quantity) external {
        vm.assume(quantity > 0 && quantity < 1_000_000);

        init();

        vm.prank(admin);
        uint256 tokenId = target.setupNewToken("test", quantity);

        vm.prank(admin);
        target.addPermission(tokenId, address(simpleMinter), minterRole);

        uint256 totalReward = target.computeTotalReward(target.mintFee(), quantity);
        vm.deal(admin, totalReward);

        vm.prank(admin);
        target.mint{value: totalReward}(simpleMinter, tokenId, quantity, defaultRewardsRecipients, abi.encode(recipient));

        IZoraCreator1155TypesV1.TokenData memory tokenData = target.getTokenInfo(tokenId);
        assertEq(tokenData.totalMinted, quantity);
        assertEq(target.balanceOf(recipient, tokenId), quantity);
    }

    function test_mint_revertOnlyMinter() external {
        init();

        vm.prank(admin);
        uint256 tokenId = target.setupNewToken("test", 1000);

        vm.expectRevert(abi.encodeWithSelector(IZoraCreator1155Errors.UserMissingRoleForToken.selector, address(0), tokenId, target.PERMISSION_BIT_MINTER()));
        target.mint(SimpleMinter(payable(address(0))), tokenId, 0, defaultRewardsRecipients, "");
    }

    function test_mint_revertCannotMintMoreTokens() external {
        init();

        uint256 totalReward = target.computeTotalReward(target.mintFee(), 1001);
        vm.deal(admin, totalReward);

        vm.startPrank(admin);

        uint256 tokenId = target.setupNewToken("test", 1000);

        target.addPermission(tokenId, address(simpleMinter), adminRole);

        vm.expectRevert(abi.encodeWithSelector(IZoraCreator1155Errors.CannotMintMoreTokens.selector, tokenId, 1001, 0, 1000));
        target.mint{value: totalReward}(simpleMinter, tokenId, 1001, defaultRewardsRecipients, abi.encode(recipient));

        vm.stopPrank();
    }

    function test_mintFee_returnsMintFee() public {
        assertEq(target.mintFee(), target.mintFee());
    }

    function test_FreeMintRewards(uint256 quantity) public {
        vm.assume(quantity > 0 && quantity < 1_000_000);

        init();

        vm.prank(admin);
        uint256 tokenId = target.setupNewToken("test", quantity);

        vm.prank(admin);
        target.addPermission(tokenId, address(simpleMinter), adminRole);

        IRewardSplits.RewardsSettings memory settings = computeFreeMintRewards(target.mintFee() * quantity);

        uint256 totalReward = target.computeTotalReward(target.mintFee(), quantity);
        vm.deal(collector, totalReward);

        vm.prank(collector);
        target.mint{value: totalReward}(simpleMinter, tokenId, quantity, defaultRewardsRecipients, abi.encode(recipient));

        (, , address fundsRecipient, , , ) = target.config();

        assertEq(protocolRewards.balanceOf(recipient), 0, "recipient");
        assertEq(protocolRewards.balanceOf(fundsRecipient), settings.creatorReward + settings.firstMinterReward, "first minter");
        assertEq(protocolRewards.balanceOf(zora), settings.zoraReward + settings.mintReferralReward + settings.createReferralReward, "zora reward");
    }

    function test_FreeMintRewardsWithCreateReferral(uint256 quantity) public {
        vm.assume(quantity > 0 && quantity < 1_000_000);

        init();

        vm.prank(admin);
        uint256 tokenId = target.setupNewTokenWithCreateReferral("test", quantity, createReferral);

        vm.prank(admin);
        target.addPermission(tokenId, address(simpleMinter), adminRole);

        uint256 totalReward = computeTotalReward(target.mintFee(), quantity);
        IRewardSplits.RewardsSettings memory settings = computeFreeMintRewards(totalReward);

        vm.deal(collector, totalReward);

        vm.prank(collector);
        target.mint{value: totalReward}(simpleMinter, tokenId, quantity, defaultRewardsRecipients, abi.encode(recipient));

        (, , address fundsRecipient, , , ) = target.config();

        assertEq(protocolRewards.balanceOf(recipient), 0, "recipient");
        assertEq(protocolRewards.balanceOf(fundsRecipient), settings.creatorReward + settings.firstMinterReward, "first minter");
        assertEq(protocolRewards.balanceOf(createReferral), settings.createReferralReward, "create referral");
        assertEq(protocolRewards.balanceOf(zora), settings.zoraReward + settings.mintReferralReward, "mint referral");
    }

    function test_FreeMintRewardsWithMintReferral(uint256 quantity) public {
        vm.assume(quantity > 0 && quantity < 1_000_000);

        init();

        vm.prank(admin);
        uint256 tokenId = target.setupNewToken("test", quantity);

        vm.prank(admin);
        target.addPermission(tokenId, address(simpleMinter), adminRole);

        IRewardSplits.RewardsSettings memory settings = computeFreeMintRewards(quantity * target.mintFee());

        uint256 totalReward = target.computeTotalReward(target.mintFee(), quantity);
        vm.deal(collector, totalReward);

        vm.prank(collector);
        target.mint{value: totalReward}(simpleMinter, tokenId, quantity, rewardsRecipients, abi.encode(recipient));

        (, , address fundsRecipient, , , ) = target.config();

        assertEq(protocolRewards.balanceOf(recipient), 0);
        assertEq(protocolRewards.balanceOf(fundsRecipient), settings.creatorReward + settings.firstMinterReward);
        assertEq(protocolRewards.balanceOf(mintReferral), settings.mintReferralReward);
        assertEq(protocolRewards.balanceOf(zora), settings.zoraReward + settings.createReferralReward);
    }

    function test_FreeMintRewardsWithCreateAndMintReferral(uint256 quantity) public {
        vm.assume(quantity > 0 && quantity < 1_000_000);

        init();

        vm.prank(admin);
        uint256 tokenId = target.setupNewTokenWithCreateReferral("test", quantity, createReferral);

        vm.prank(admin);
        target.addPermission(tokenId, address(simpleMinter), adminRole);

        uint256 totalReward = computeTotalReward(target.mintFee(), quantity);
        IRewardSplits.RewardsSettings memory settings = computeFreeMintRewards(totalReward);

        vm.deal(collector, totalReward);

        vm.prank(collector);
        target.mint{value: totalReward}(simpleMinter, tokenId, quantity, rewardsRecipients, abi.encode(recipient));

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
        vm.expectRevert();
        target.mint(simpleMinter, tokenId, quantity, defaultRewardsRecipients, abi.encode(recipient));
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

        IRewardSplits.RewardsSettings memory settings = computePaidMintRewards(target.mintFee() * quantity);

        uint256 totalReward = target.computeTotalReward(target.mintFee(), quantity);
        uint256 totalSale = quantity * salePrice;
        uint256 totalValue = totalReward + totalSale;

        vm.deal(collector, totalValue);

        vm.prank(collector);
        target.mint{value: totalValue}(fixedPriceMinter, tokenId, quantity, defaultRewardsRecipients, abi.encode(recipient));

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

        IRewardSplits.RewardsSettings memory settings = computePaidMintRewards(quantity * target.mintFee());

        uint256 totalReward = target.computeTotalReward(target.mintFee(), quantity);
        uint256 totalSale = quantity * salePrice;
        uint256 totalValue = totalReward + totalSale;

        vm.deal(collector, totalValue);

        vm.prank(collector);
        target.mint{value: totalValue}(fixedPriceMinter, tokenId, quantity, rewardsRecipients, abi.encode(recipient));

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

        IRewardSplits.RewardsSettings memory settings = computePaidMintRewards(quantity * target.mintFee());

        uint256 totalReward = target.computeTotalReward(target.mintFee(), quantity);
        uint256 totalSale = quantity * salePrice;
        uint256 totalValue = totalReward + totalSale;

        vm.deal(collector, totalValue);

        vm.prank(collector);
        target.mint{value: totalValue}(fixedPriceMinter, tokenId, quantity, defaultRewardsRecipients, abi.encode(recipient));

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

        IRewardSplits.RewardsSettings memory settings = computePaidMintRewards(quantity * target.mintFee());

        uint256 totalReward = target.computeTotalReward(target.mintFee(), quantity);
        uint256 totalSale = quantity * salePrice;
        uint256 totalValue = totalReward + totalSale;

        vm.deal(collector, totalValue);

        vm.prank(collector);
        target.mint{value: totalValue}(fixedPriceMinter, tokenId, quantity, rewardsRecipients, abi.encode(recipient));

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
        vm.expectRevert();
        target.mint(fixedPriceMinter, tokenId, quantity, defaultRewardsRecipients, abi.encode(recipient));
    }

    function test_FirstMinterRewardReceivedOnConsecutiveMints(uint32 quantity) public {
        vm.assume(quantity > 0 && quantity < type(uint200).max);

        init();

        PremintConfigV2 memory premintConfig = PremintConfigV2({
            tokenConfig: TokenCreationConfigV2({
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
                payoutRecipient: admin,
                royaltyBPS: 0,
                // Fixed price minter address
                fixedPriceMinter: address(fixedPriceMinter),
                // Default create referral
                createReferral: address(0)
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

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            adminKey,
            ZoraCreator1155Attribution.premintHashedTypeDataV4(
                ZoraCreator1155Attribution.hashPremint(premintConfig),
                address(target),
                PremintEncoding.HASHED_VERSION_2,
                chainId
            )
        );

        bytes memory signature = abi.encodePacked(r, s, v);

        vm.prank(collector);
        uint256 tokenId;

        {
            tokenId = target.delegateSetupNewToken(abi.encode(premintConfig), PremintEncoding.HASHED_VERSION_2, signature, collectors[0], address(0));
        }

        uint256 totalReward = computeTotalReward(target.mintFee(), quantity);
        IRewardSplits.RewardsSettings memory settings = computeFreeMintRewards(totalReward);

        vm.deal(collectors[1], totalReward);
        vm.prank(collectors[1]);
        target.mint{value: totalReward}(fixedPriceMinter, tokenId, quantity, defaultRewardsRecipients, abi.encode(collectors[1]));

        assertEq(protocolRewards.balanceOf(collectors[0]), settings.firstMinterReward);

        vm.deal(collectors[2], totalReward);

        vm.prank(collectors[2]);
        target.mint{value: totalReward}(fixedPriceMinter, tokenId, quantity, defaultRewardsRecipients, abi.encode(collectors[2]));

        assertEq(protocolRewards.balanceOf(collectors[0]), settings.firstMinterReward * 2);
    }

    function test_AssumeFirstMinterRecipientIsAddress(uint256 quantity) public {
        vm.assume(quantity > 0 && quantity < 1_000_000);

        init();

        vm.prank(admin);
        uint256 tokenId = target.setupNewToken("test", quantity);

        vm.prank(admin);
        target.addPermission(tokenId, address(simpleMinter), adminRole);

        IRewardSplits.RewardsSettings memory settings = computeFreeMintRewards(target.mintFee() * quantity);
        uint256 totalReward = computeTotalReward(target.mintFee(), quantity);

        vm.deal(collector, totalReward);

        uint256 mintRecipient = 1234;

        address[] memory rewardsRecipientsArray = new address[](1);
        rewardsRecipientsArray[0] = makeAddr("rewardRecipient");

        vm.prank(collector);
        target.mint{value: totalReward}(simpleMinter, tokenId, quantity, rewardsRecipientsArray, abi.encode(mintRecipient));

        (, , address fundsRecipient, , , ) = target.config();

        assertEq(protocolRewards.balanceOf(address(uint160(mintRecipient))), 0);
        assertEq(protocolRewards.balanceOf(rewardsRecipientsArray[0]), settings.mintReferralReward);
        assertEq(protocolRewards.balanceOf(fundsRecipient), settings.creatorReward + settings.firstMinterReward);
        assertEq(protocolRewards.balanceOf(zora), settings.zoraReward + settings.createReferralReward);
    }

    function test_SetCreatorRewardRecipientForToken() public {
        address collaborator = makeAddr("collaborator");
        uint256 quantity = 100;

        init();

        vm.prank(admin);
        uint256 tokenId = target.setupNewToken("test", quantity);

        address creatorRewardRecipient;

        creatorRewardRecipient = target.getCreatorRewardRecipient(tokenId);

        ICreatorRoyaltiesControl.RoyaltyConfiguration memory newRoyaltyConfig = ICreatorRoyaltiesControl.RoyaltyConfiguration(0, 0, collaborator);

        vm.prank(admin);
        target.updateRoyaltiesForToken(tokenId, newRoyaltyConfig);

        creatorRewardRecipient = target.getCreatorRewardRecipient(tokenId);

        assertEq(creatorRewardRecipient, collaborator);

        vm.prank(admin);
        target.addPermission(tokenId, address(simpleMinter), adminRole);

        IRewardSplits.RewardsSettings memory settings = computeFreeMintRewards(quantity * target.mintFee());

        uint256 totalReward = target.computeTotalReward(target.mintFee(), quantity);
        vm.deal(collector, totalReward);

        vm.prank(collector);
        vm.expectEmit(true, true, true, true);
        emit RewardsDeposit(
            collaborator,
            zora,
            zora,
            collaborator,
            zora,
            address(target),
            settings.creatorReward,
            settings.createReferralReward,
            settings.mintReferralReward,
            settings.firstMinterReward,
            settings.zoraReward
        );
        target.mint{value: totalReward}(simpleMinter, tokenId, quantity, defaultRewardsRecipients, abi.encode(recipient));

        assertEq(protocolRewards.balanceOf(collaborator), settings.creatorReward + settings.firstMinterReward);
    }

    function test_CreatorRewardRecipientConditionalAddress() public {
        ICreatorRoyaltiesControl.RoyaltyConfiguration memory royaltyConfig;
        address creatorRewardRecipient;

        address collaborator = makeAddr("collaborator");
        uint256 quantity = 100;

        init();

        vm.prank(admin);
        uint256 tokenId = target.setupNewToken("test", quantity);

        (, , address contractFundsRecipient, , , ) = target.config();

        creatorRewardRecipient = target.getCreatorRewardRecipient(tokenId);
        assertEq(creatorRewardRecipient, contractFundsRecipient);

        royaltyConfig = ICreatorRoyaltiesControl.RoyaltyConfiguration(0, 0, collaborator);
        vm.prank(admin);
        target.updateRoyaltiesForToken(tokenId, royaltyConfig);

        creatorRewardRecipient = target.getCreatorRewardRecipient(tokenId);
        assertEq(creatorRewardRecipient, collaborator);

        royaltyConfig = ICreatorRoyaltiesControl.RoyaltyConfiguration(0, 0, address(0));
        vm.prank(admin);
        target.updateRoyaltiesForToken(tokenId, royaltyConfig);

        vm.prank(admin);
        target.setFundsRecipient(payable(address(0)));

        creatorRewardRecipient = target.getCreatorRewardRecipient(tokenId);
        assertEq(creatorRewardRecipient, address(target));
    }

    function test_ContractAsCreatorRewardRecipientFallback() public {
        uint256 quantity = 100;

        init();

        vm.startPrank(admin);
        uint256 tokenId = target.setupNewToken("test", quantity);

        target.setFundsRecipient(payable(address(0)));

        target.addPermission(tokenId, address(simpleMinter), adminRole);
        vm.stopPrank();

        IRewardSplits.RewardsSettings memory settings = computeFreeMintRewards(quantity * target.mintFee());

        uint256 totalReward = target.computeTotalReward(target.mintFee(), quantity);
        vm.deal(collector, totalReward);

        address creatorRewardRecipient = target.getCreatorRewardRecipient(tokenId);

        vm.prank(collector);
        target.mint{value: totalReward}(simpleMinter, tokenId, quantity, defaultRewardsRecipients, abi.encode(recipient));

        assertEq(creatorRewardRecipient, address(target));

        uint256 creatorRewardBalance = settings.creatorReward + settings.firstMinterReward;
        assertEq(protocolRewards.balanceOf(address(target)), creatorRewardBalance);

        protocolRewards.withdrawFor(address(target), creatorRewardBalance);

        vm.prank(admin);
        target.withdraw();

        assertEq(address(0).balance, creatorRewardBalance);
        assertEq(protocolRewards.balanceOf(address(target)), 0);
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

        uint256 totalReward = target.computeTotalReward(target.mintFee(), quantity);

        vm.expectRevert(abi.encodeWithSignature("WrongValueSent()"));
        target.mint{value: totalReward}(fixedPriceMinter, tokenId, quantity, defaultRewardsRecipients, abi.encode(recipient));
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
        vm.expectEmit(true, true, true, true);
        emit ContractURIUpdated();
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

        bytes4 reduceSupplyInterfaceId = type(IReduceSupply).interfaceId;
        assertTrue(target.supportsInterface(reduceSupplyInterfaceId));

        bytes4 hasContractNameInterfaceId = type(IHasContractName).interfaceId;
        assertTrue(target.supportsInterface(hasContractNameInterfaceId));
    }

    function test_burnBatch() external {
        init();

        vm.prank(admin);
        uint256 tokenId = target.setupNewToken("test", 10);

        vm.prank(admin);
        target.addPermission(tokenId, address(simpleMinter), adminRole);

        uint256 totalReward = target.computeTotalReward(target.mintFee(), 5);
        vm.deal(admin, totalReward);

        vm.prank(admin);
        target.mint{value: totalReward}(simpleMinter, tokenId, 5, defaultRewardsRecipients, abi.encode(recipient));

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

        uint256 totalReward = target.computeTotalReward(target.mintFee(), 5);
        vm.deal(admin, totalReward);

        vm.prank(admin);
        target.mint{value: totalReward}(simpleMinter, tokenId, 5, defaultRewardsRecipients, abi.encode(recipient));

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

        uint256 totalReward = target.computeTotalReward(target.mintFee(), 1000);
        uint256 totalSale = 1 ether;
        uint256 totalValue = totalReward + totalSale;

        vm.deal(admin, totalValue);

        vm.prank(admin);
        target.mint{value: totalValue}(simpleMinter, tokenId, 1000, defaultRewardsRecipients, abi.encode(recipient));

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

        uint256 totalReward = target.computeTotalReward(target.mintFee(), 1000);
        uint256 totalSale = 1 ether;
        uint256 totalValue = totalReward + totalSale;

        vm.deal(admin, totalValue);
        vm.prank(admin);
        target.mint{value: totalValue}(simpleMinter, tokenId, 1000, defaultRewardsRecipients, abi.encode(recipient));

        vm.expectRevert(abi.encodeWithSelector(IZoraCreator1155Errors.ETHWithdrawFailed.selector, simpleMinter, 1 ether));
        vm.prank(address(simpleMinter));
        target.withdraw();
    }

    function test_unauthorizedUpgradeFails() external {
        address new1155Impl = address(new ZoraCreator1155Impl(zora, address(0x1234), address(protocolRewards), address(0)));

        vm.expectRevert();
        target.upgradeTo(new1155Impl);
    }

    function test_authorizedUpgrade() external {
        init();
        address[] memory oldImpls = new address[](1);

        oldImpls[0] = address(zoraCreator1155Impl);

        address new1155Impl = address(new ZoraCreator1155Impl(zora, address(0x1234), address(protocolRewards), makeAddr("timedSaleStrategy")));

        vm.prank(upgradeGate.owner());
        upgradeGate.registerUpgradePath(oldImpls, new1155Impl);

        vm.prank(admin);
        target.upgradeTo(new1155Impl);

        vm.prank(admin);
        uint256 tokenId = target.setupNewToken("test", 1000);

        vm.prank(admin);
        target.adminMint(address(0x1234), tokenId, 1, "");
    }

    function test_FreeMintRewardsWithrewardsRecipients(uint256 quantity) public {
        vm.assume(quantity > 0 && quantity < 1_000_000);

        init();

        vm.prank(admin);
        uint256 tokenId = target.setupNewToken("test", quantity);

        vm.prank(admin);
        target.addPermission(tokenId, address(simpleMinter), adminRole);

        IRewardSplits.RewardsSettings memory settings = computeFreeMintRewards(target.mintFee() * quantity);

        uint256 totalReward = target.computeTotalReward(target.mintFee(), quantity);
        vm.deal(collector, totalReward);

        vm.prank(collector);
        target.mint{value: totalReward}(simpleMinter, tokenId, quantity, rewardsRecipients, abi.encode(recipient));

        (, , address fundsRecipient, , , ) = target.config();

        assertEq(protocolRewards.balanceOf(recipient), 0);
        assertEq(protocolRewards.balanceOf(fundsRecipient), settings.creatorReward + settings.firstMinterReward);
        assertEq(protocolRewards.balanceOf(zora), settings.zoraReward + settings.createReferralReward);
        assertEq(protocolRewards.balanceOf(mintReferral), settings.mintReferralReward);
    }

    function test_PaidMintRewardsWithRewardsArgument(uint256 quantity, uint256 salePrice) public {
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

        IRewardSplits.RewardsSettings memory settings = computePaidMintRewards(quantity * target.mintFee());

        uint256 totalReward = target.computeTotalReward(target.mintFee(), quantity);
        uint256 totalSale = quantity * salePrice;
        uint256 totalValue = totalReward + totalSale;

        vm.deal(collector, totalValue);

        vm.prank(collector);
        target.mint{value: totalValue}(fixedPriceMinter, tokenId, quantity, rewardsRecipients, abi.encode(recipient));

        assertEq(address(target).balance, totalSale);
        assertEq(protocolRewards.balanceOf(admin), settings.firstMinterReward);
        assertEq(protocolRewards.balanceOf(zora), settings.zoraReward + settings.createReferralReward);
        assertEq(protocolRewards.balanceOf(mintReferral), settings.mintReferralReward);
    }

    function testRevert_InsufficientEthForFreeMintRewardsWithRewardsArgument(uint256 quantity) public {
        vm.assume(quantity > 0 && quantity < type(uint200).max);

        init();

        vm.prank(admin);
        uint256 tokenId = target.setupNewToken("test", quantity);

        vm.prank(admin);
        target.addPermission(tokenId, address(simpleMinter), adminRole);

        vm.prank(collector);
        vm.expectRevert();
        target.mint(simpleMinter, tokenId, quantity, rewardsRecipients, abi.encode(recipient));
    }

    function test_mintWithEth() public {
        init();
        uint256 tokenPrice = 1 ether;

        vm.prank(admin);
        uint256 tokenId = target.setupNewToken("test", 1);

        vm.prank(admin);
        target.addPermission(tokenId, address(simpleMinter), adminRole);
        vm.stopPrank();

        vm.deal(collector, tokenPrice);
        vm.prank(collector);
        target.mint{value: tokenPrice + target.mintFee()}(simpleMinter, tokenId, 1, rewardsRecipients, abi.encode(recipient));

        IRewardSplits.RewardsSettings memory settings = computePaidMintRewards(target.mintFee());

        assertEq(protocolRewards.balanceOf(admin), settings.firstMinterReward + settings.creatorReward);
        assertEq(protocolRewards.balanceOf(recipient), 0);
        assertEq(protocolRewards.balanceOf(zora), settings.zoraReward + settings.createReferralReward);
        assertEq(protocolRewards.balanceOf(mintReferral), settings.mintReferralReward);
    }

    function test_mintWithVariablePrice(uint256 tokenPrice, uint256 quantity) public {
        vm.assume(tokenPrice > 0 && tokenPrice < type(uint200).max);
        vm.assume(quantity > 0 && quantity < 1_000_000);
        init();

        vm.prank(admin);
        uint256 tokenId = target.setupNewToken("test", quantity);

        vm.prank(admin);
        target.addPermission(tokenId, address(simpleMinter), adminRole);
        vm.stopPrank();

        uint256 totalReward = target.computeTotalReward(target.mintFee(), quantity);
        uint256 totalValue = totalReward + tokenPrice;

        vm.deal(collector, totalValue);
        vm.prank(collector);

        // mint only 1 token for the first mint
        target.mint{value: totalValue}(simpleMinter, tokenId, 1, rewardsRecipients, abi.encode(recipient));

        IRewardSplits.RewardsSettings memory settings = computePaidMintRewards(target.mintFee());
        uint256 firstMintAdminBalance = settings.firstMinterReward + settings.creatorReward;
        uint256 firstMintZoraBalance = settings.zoraReward + settings.createReferralReward;
        uint256 firstMintMintReferralBalance = settings.mintReferralReward;

        assertEq(protocolRewards.balanceOf(admin), firstMintAdminBalance);
        assertEq(protocolRewards.balanceOf(recipient), 0);
        assertEq(protocolRewards.balanceOf(zora), firstMintZoraBalance);
        assertEq(protocolRewards.balanceOf(mintReferral), firstMintMintReferralBalance);

        // update quanity to be fuzzy value - 1
        quantity = quantity - 1;

        totalReward = target.computeTotalReward(target.mintFee(), quantity);
        totalValue = totalReward + tokenPrice;

        // test mint with fuzzy quantity, tokenPrice, and mintTicketPrice
        vm.deal(collector, totalValue);
        vm.prank(collector);
        target.mint{value: totalValue}(simpleMinter, tokenId, quantity, rewardsRecipients, abi.encode(recipient));

        settings = computePaidMintRewards(target.mintFee() * quantity);

        assertEq(protocolRewards.balanceOf(admin), settings.firstMinterReward + settings.creatorReward + firstMintAdminBalance);
        assertEq(protocolRewards.balanceOf(recipient), 0);
        assertEq(protocolRewards.balanceOf(zora), settings.zoraReward + settings.createReferralReward + firstMintZoraBalance);
        assertEq(protocolRewards.balanceOf(mintReferral), settings.mintReferralReward + firstMintMintReferralBalance);
    }

    function test_ReduceSupply() public {
        init();

        uint256 initialMaxSupply = 1_000_000;

        vm.startPrank(admin);

        uint256 tokenId = target.setupNewToken("test", initialMaxSupply);
        target.addPermission(tokenId, address(simpleMinter), minterRole);

        vm.stopPrank();

        uint256 quantity = 11;
        uint256 totalReward = target.mintFee() * quantity;

        vm.deal(collector, totalReward);
        vm.prank(collector);
        target.mint{value: totalReward}(simpleMinter, tokenId, quantity, rewardsRecipients, abi.encode(recipient));

        IZoraCreator1155.TokenData memory tokenData = target.getTokenInfo(tokenId);

        assertEq(tokenData.totalMinted, quantity);
        assertEq(tokenData.maxSupply, initialMaxSupply);

        uint256 totalSupply = target.getTokenInfo(tokenId).totalMinted;
        simpleMinter.settleMint(address(target), tokenId, totalSupply);

        tokenData = target.getTokenInfo(tokenId);

        assertEq(tokenData.maxSupply, totalSupply);

        vm.deal(collector, totalReward);
        vm.prank(collector);
        vm.expectRevert(abi.encodeWithSignature("CannotMintMoreTokens(uint256,uint256,uint256,uint256)", 1, 11, 11, 11));
        target.mint{value: totalReward}(simpleMinter, tokenId, quantity, rewardsRecipients, abi.encode(recipient));
    }

    function test_ReduceSupply_newSupplyGreaterThanMaxIsOkay() public {
        init();

        uint256 initialMaxSupply = 1_000_000;

        vm.startPrank(admin);

        uint256 tokenId = target.setupNewToken("test", initialMaxSupply);
        target.addPermission(tokenId, address(simpleMinter), minterRole);

        simpleMinter.settleMint(address(target), tokenId, initialMaxSupply + 1000);
    }

    function test_ReduceSupply_revertsWhen_newSupplyLessThanTotalMinted() public {
        init();

        uint256 initialMaxSupply = 1_000_000;

        vm.startPrank(admin);

        uint256 tokenId = target.setupNewToken("test", initialMaxSupply);
        target.addPermission(tokenId, address(simpleMinter), minterRole);

        vm.stopPrank();

        uint256 quantity = 11;
        uint256 totalReward = target.mintFee() * quantity;

        vm.deal(collector, totalReward);
        vm.prank(collector);
        target.mint{value: totalReward}(simpleMinter, tokenId, quantity, rewardsRecipients, abi.encode(recipient));

        vm.expectRevert(IZoraCreator1155Errors.CannotReduceMaxSupplyBelowMinted.selector);
        simpleMinter.settleMint(address(target), tokenId, quantity - 1);
    }

    function testRevert_ReduceSupplyInvalidPermission() public {
        init();

        uint256 initialMaxSupply = 1_000_000;

        vm.startPrank(admin);

        uint256 tokenId = target.setupNewToken("test", initialMaxSupply);
        target.addPermission(tokenId, address(simpleMinter), minterRole);

        vm.stopPrank();

        uint256 quantity = 11;
        uint256 totalReward = target.mintFee() * quantity;

        vm.deal(collector, totalReward);
        vm.prank(collector);
        target.mint{value: totalReward}(simpleMinter, tokenId, quantity, rewardsRecipients, abi.encode(recipient));

        vm.prank(admin);
        target.removePermission(tokenId, address(simpleMinter), minterRole);

        vm.expectRevert(IZoraCreator1155Errors.OnlyAllowedForRegisteredMinter.selector);
        simpleMinter.settleMint(address(target), tokenId, 0);
    }

    function testRevert_ReduceSupplyInvalidPermissionNotFromTimedSaleStrategy() public {
        init();

        uint256 initialMaxSupply = 1_000_000;

        vm.startPrank(admin);

        uint256 tokenId = target.setupNewToken("test", initialMaxSupply);
        target.addPermission(tokenId, address(admin), minterRole);

        vm.expectRevert(IZoraCreator1155Errors.OnlyAllowedForTimedSaleStrategy.selector);
        target.reduceSupply(tokenId, 100000);
    }
}
