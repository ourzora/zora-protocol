// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import {RewardsManager} from "../../src/rewards/RewardsManager.sol";
import {ZoraCreator1155Impl} from "../../src/nft/ZoraCreator1155Impl.sol";
import {Zora1155} from "../../src/proxies/Zora1155.sol";
import {ZoraCreatorFixedPriceSaleStrategy} from "../../src/minters/fixed-price/ZoraCreatorFixedPriceSaleStrategy.sol";
import {IZoraCreator1155TypesV1} from "../../src/nft/IZoraCreator1155TypesV1.sol";
import {ICreatorRoyaltiesControl} from "../../src/interfaces/ICreatorRoyaltiesControl.sol";

import {MockUpgradeGate} from "../mock/MockUpgradeGate.sol";
import {SimpleMinter} from "../mock/SimpleMinter.sol";
import {RewardsUtils} from "../utils/RewardsUtils.sol";

contract RewardsTest is Test, RewardsUtils {
    RewardsManager internal rewardsManager;
    ZoraCreator1155Impl internal zoraCreator1155Impl;
    ZoraCreator1155Impl internal target;
    MockUpgradeGate internal upgradeGate;
    SimpleMinter internal freeMinter;
    ZoraCreatorFixedPriceSaleStrategy internal fixedPriceMinter;

    uint256 internal adminRole;
    uint256 internal minterRole;
    uint256 internal fundsManagerRole;
    uint256 internal metadataRole;

    address internal zora;
    address internal creator;
    address internal buyer;
    address internal finder;
    address internal lister;

    function setUp() external {
        zora = makeAddr("zora");
        creator = makeAddr("creator");
        buyer = makeAddr("buyer");
        finder = makeAddr("finder");
        lister = makeAddr("lister");

        upgradeGate = new MockUpgradeGate();
        upgradeGate.initialize(zora);
        rewardsManager = new RewardsManager();
        zoraCreator1155Impl = new ZoraCreator1155Impl(address(rewardsManager), zora, address(upgradeGate));
        target = ZoraCreator1155Impl(address(new Zora1155(address(zoraCreator1155Impl))));
        target.initialize("test", "test", ICreatorRoyaltiesControl.RoyaltyConfiguration(0, 0, address(0)), payable(creator), new bytes[](0));

        adminRole = target.PERMISSION_BIT_ADMIN();
        minterRole = target.PERMISSION_BIT_MINTER();
        fundsManagerRole = target.PERMISSION_BIT_FUNDS_MANAGER();
        metadataRole = target.PERMISSION_BIT_METADATA();

        freeMinter = new SimpleMinter();
        fixedPriceMinter = new ZoraCreatorFixedPriceSaleStrategy();
    }

    function test_FreeMintRewards(uint256 numTokens) public {
        vm.assume(numTokens < FREE_MINT_MAX_TOKEN_QUANTITY);

        vm.startPrank(creator);
        uint256 tokenId = target.setupNewToken("test", numTokens);
        target.addPermission(tokenId, address(freeMinter), adminRole);
        vm.stopPrank();

        (uint256 totalReward, uint256 creatorReward, uint256 zoraReward, uint256 finderReward, uint256 listerReward) = computeFreeMintRewards(numTokens);

        vm.deal(buyer, totalReward);

        vm.prank(buyer);
        target.mint{value: totalReward}(freeMinter, tokenId, numTokens, abi.encode(buyer), address(0), address(0));

        assertEq(rewardsManager.balanceOf(creator), creatorReward);
        assertEq(rewardsManager.balanceOf(zora), zoraReward + finderReward + listerReward);
    }

    function test_FreeMintRewardsWithFinder(uint256 numTokens) public {
        vm.assume(numTokens < FREE_MINT_MAX_TOKEN_QUANTITY);

        vm.startPrank(creator);
        uint256 tokenId = target.setupNewToken("test", numTokens);
        target.addPermission(tokenId, address(freeMinter), adminRole);
        vm.stopPrank();

        (uint256 totalReward, uint256 creatorReward, uint256 zoraReward, uint256 finderReward, uint256 listerReward) = computeFreeMintRewards(numTokens);

        vm.deal(buyer, totalReward);

        vm.prank(buyer);
        target.mint{value: totalReward}(freeMinter, tokenId, numTokens, abi.encode(buyer), finder, address(0));

        assertEq(rewardsManager.balanceOf(creator), creatorReward);
        assertEq(rewardsManager.balanceOf(zora), zoraReward + listerReward);
        assertEq(rewardsManager.balanceOf(finder), finderReward);
    }

    function test_FreeMintRewardsWithLister(uint256 numTokens) public {
        vm.assume(numTokens < FREE_MINT_MAX_TOKEN_QUANTITY);

        vm.startPrank(creator);
        uint256 tokenId = target.setupNewToken("test", numTokens);
        target.addPermission(tokenId, address(freeMinter), adminRole);
        vm.stopPrank();

        (uint256 totalReward, uint256 creatorReward, uint256 zoraReward, uint256 finderReward, uint256 listerReward) = computeFreeMintRewards(numTokens);

        vm.deal(buyer, totalReward);

        vm.prank(buyer);
        target.mint{value: totalReward}(freeMinter, tokenId, numTokens, abi.encode(buyer), address(0), lister);

        assertEq(rewardsManager.balanceOf(creator), creatorReward);
        assertEq(rewardsManager.balanceOf(zora), zoraReward + finderReward);
        assertEq(rewardsManager.balanceOf(lister), listerReward);
    }

    function test_FreeMintRewardsWithFinderAndLister(uint256 numTokens) public {
        vm.assume(numTokens < FREE_MINT_MAX_TOKEN_QUANTITY);

        vm.startPrank(creator);
        uint256 tokenId = target.setupNewToken("test", numTokens);
        target.addPermission(tokenId, address(freeMinter), adminRole);
        vm.stopPrank();

        (uint256 totalReward, uint256 creatorReward, uint256 zoraReward, uint256 finderReward, uint256 listerReward) = computeFreeMintRewards(numTokens);

        vm.deal(buyer, totalReward);

        vm.prank(buyer);
        target.mint{value: totalReward}(freeMinter, tokenId, numTokens, abi.encode(buyer), finder, lister);

        assertEq(rewardsManager.balanceOf(creator), creatorReward);
        assertEq(rewardsManager.balanceOf(zora), zoraReward);
        assertEq(rewardsManager.balanceOf(finder), finderReward);
        assertEq(rewardsManager.balanceOf(lister), listerReward);
    }

    function test_FixedPriceMintRewards(uint256 numTokens) public {
        uint96 pricePerToken = 1 ether;
        uint256 maxTokens = type(uint96).max / pricePerToken;

        vm.assume(numTokens < maxTokens);

        vm.startPrank(creator);

        uint256 newTokenId = target.setupNewToken("https://zora.co/testing/token.json", numTokens);
        target.addPermission(newTokenId, address(fixedPriceMinter), target.PERMISSION_BIT_MINTER());

        ZoraCreatorFixedPriceSaleStrategy.SalesConfig memory saleConfig = ZoraCreatorFixedPriceSaleStrategy.SalesConfig({
            pricePerToken: pricePerToken,
            saleStart: 0,
            saleEnd: type(uint64).max,
            maxTokensPerAddress: 0,
            fundsRecipient: creator
        });
        target.callSale(newTokenId, fixedPriceMinter, abi.encodeWithSelector(ZoraCreatorFixedPriceSaleStrategy.setSale.selector, newTokenId, saleConfig));

        vm.stopPrank();

        uint256 creatorBeforeBalance = creator.balance;

        (uint256 totalReward, , , ) = computePaidMintRewards(numTokens);

        uint256 totalPrice = saleConfig.pricePerToken * numTokens;

        vm.deal(buyer, totalPrice + totalReward);

        vm.prank(buyer);
        target.mint{value: totalPrice + totalReward}(fixedPriceMinter, newTokenId, numTokens, abi.encode(creator, ""), address(0), address(0));

        assertEq(creator.balance - creatorBeforeBalance, totalPrice);
        assertEq(rewardsManager.balanceOf(zora), totalReward);
    }

    function test_FixedPriceMintRewardsWithFinder(uint256 numTokens) public {
        uint96 pricePerToken = 1 ether;
        uint256 maxTokens = type(uint96).max / pricePerToken;

        vm.assume(numTokens < maxTokens);

        vm.startPrank(creator);

        uint256 newTokenId = target.setupNewToken("https://zora.co/testing/token.json", numTokens);
        target.addPermission(newTokenId, address(fixedPriceMinter), target.PERMISSION_BIT_MINTER());

        ZoraCreatorFixedPriceSaleStrategy.SalesConfig memory saleConfig = ZoraCreatorFixedPriceSaleStrategy.SalesConfig({
            pricePerToken: pricePerToken,
            saleStart: 0,
            saleEnd: type(uint64).max,
            maxTokensPerAddress: 0,
            fundsRecipient: creator
        });
        target.callSale(newTokenId, fixedPriceMinter, abi.encodeWithSelector(ZoraCreatorFixedPriceSaleStrategy.setSale.selector, newTokenId, saleConfig));

        vm.stopPrank();

        uint256 creatorBeforeBalance = creator.balance;

        (uint256 totalReward, uint256 zoraReward, uint256 finderReward, uint256 listerReward) = computePaidMintRewards(numTokens);

        uint256 totalPrice = saleConfig.pricePerToken * numTokens;

        vm.deal(buyer, totalPrice + totalReward);

        vm.prank(buyer);
        target.mint{value: totalPrice + totalReward}(fixedPriceMinter, newTokenId, numTokens, abi.encode(creator, ""), finder, address(0));

        assertEq(creator.balance - creatorBeforeBalance, totalPrice);
        assertEq(rewardsManager.balanceOf(zora), zoraReward + listerReward);
        assertEq(rewardsManager.balanceOf(finder), finderReward);
    }

    function test_FixedPriceMintRewardsWithLister(uint256 numTokens) public {
        uint96 pricePerToken = 1 ether;
        uint256 maxTokens = type(uint96).max / pricePerToken;

        vm.assume(numTokens < maxTokens);

        vm.startPrank(creator);

        uint256 newTokenId = target.setupNewToken("https://zora.co/testing/token.json", numTokens);
        target.addPermission(newTokenId, address(fixedPriceMinter), target.PERMISSION_BIT_MINTER());

        ZoraCreatorFixedPriceSaleStrategy.SalesConfig memory saleConfig = ZoraCreatorFixedPriceSaleStrategy.SalesConfig({
            pricePerToken: pricePerToken,
            saleStart: 0,
            saleEnd: type(uint64).max,
            maxTokensPerAddress: 0,
            fundsRecipient: creator
        });
        target.callSale(newTokenId, fixedPriceMinter, abi.encodeWithSelector(ZoraCreatorFixedPriceSaleStrategy.setSale.selector, newTokenId, saleConfig));

        vm.stopPrank();

        uint256 creatorBeforeBalance = creator.balance;

        (uint256 totalReward, uint256 zoraReward, uint256 finderReward, uint256 listerReward) = computePaidMintRewards(numTokens);

        uint256 totalPrice = saleConfig.pricePerToken * numTokens;

        vm.deal(buyer, totalPrice + totalReward);

        vm.prank(buyer);
        target.mint{value: totalPrice + totalReward}(fixedPriceMinter, newTokenId, numTokens, abi.encode(creator, ""), address(0), lister);

        assertEq(creator.balance - creatorBeforeBalance, totalPrice);
        assertEq(rewardsManager.balanceOf(zora), zoraReward + finderReward);
        assertEq(rewardsManager.balanceOf(lister), listerReward);
    }

    function test_FixedPriceMintRewardsWithFinderAndLister(uint256 numTokens) public {
        uint96 pricePerToken = 1 ether;
        uint256 maxTokens = type(uint96).max / pricePerToken;

        vm.assume(numTokens < maxTokens);

        vm.startPrank(creator);

        uint256 newTokenId = target.setupNewToken("https://zora.co/testing/token.json", numTokens);
        target.addPermission(newTokenId, address(fixedPriceMinter), target.PERMISSION_BIT_MINTER());

        ZoraCreatorFixedPriceSaleStrategy.SalesConfig memory saleConfig = ZoraCreatorFixedPriceSaleStrategy.SalesConfig({
            pricePerToken: pricePerToken,
            saleStart: 0,
            saleEnd: type(uint64).max,
            maxTokensPerAddress: 0,
            fundsRecipient: creator
        });
        target.callSale(newTokenId, fixedPriceMinter, abi.encodeWithSelector(ZoraCreatorFixedPriceSaleStrategy.setSale.selector, newTokenId, saleConfig));

        vm.stopPrank();

        uint256 creatorBeforeBalance = creator.balance;

        (uint256 totalReward, uint256 zoraReward, uint256 finderReward, uint256 listerReward) = computePaidMintRewards(numTokens);

        uint256 totalPrice = saleConfig.pricePerToken * numTokens;

        vm.deal(buyer, totalPrice + totalReward);

        vm.prank(buyer);
        target.mint{value: totalPrice + totalReward}(fixedPriceMinter, newTokenId, numTokens, abi.encode(creator, ""), finder, lister);

        assertEq(creator.balance - creatorBeforeBalance, totalPrice);
        assertEq(rewardsManager.balanceOf(zora), zoraReward);
        assertEq(rewardsManager.balanceOf(finder), finderReward);
        assertEq(rewardsManager.balanceOf(lister), listerReward);
    }
}
