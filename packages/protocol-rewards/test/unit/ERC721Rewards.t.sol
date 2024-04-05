// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "../ProtocolRewardsTest.sol";
import {IRewardSplits} from "../../src/interfaces/IRewardSplits.sol";
import {RewardSplitsLib} from "../../src/abstract/RewardSplits.sol";

contract ERC721RewardsTest is ProtocolRewardsTest {
    MockERC721 internal mockERC721;

    function setUp() public override {
        super.setUp();

        mockERC721 = new MockERC721(creator, createReferral, address(protocolRewards), zora);

        vm.label(address(mockERC721), "MOCK_ERC721");
    }

    function computeFreeMintRewards(uint256 value) private pure returns (IRewardSplits.RewardsSettings memory) {
        return RewardSplitsLib.getRewards(false, value);
    }

    function computePaidMintRewards(uint256 value) private pure returns (IRewardSplits.RewardsSettings memory) {
        return RewardSplitsLib.getRewards(true, value);
    }

    function testValidateFreeMintTotalComputation(uint256 numTokens) public {
        vm.assume(numTokens > 0 && numTokens < 10_000);
        uint256 expectedTotal = mockERC721.computeTotalReward(0.000777 ether, numTokens);

        IRewardSplits.RewardsSettings memory settings = computeFreeMintRewards(numTokens * 0.000777 ether);

        uint256 actualTotal = settings.creatorReward +
            settings.createReferralReward +
            settings.mintReferralReward +
            settings.firstMinterReward +
            settings.zoraReward;

        assertEq(expectedTotal, actualTotal);
    }

    function testValidatePaidMintTotalComputation(uint256 numTokens) public {
        vm.assume(numTokens > 0 && numTokens < 10_000);
        uint256 expectedTotal = mockERC721.computeTotalReward(0.000777 ether, numTokens);

        IRewardSplits.RewardsSettings memory settings = computePaidMintRewards(numTokens * 0.000777 ether);

        uint256 actualTotal = settings.mintReferralReward + settings.createReferralReward + settings.firstMinterReward + settings.zoraReward;

        assertEq(expectedTotal, actualTotal);
    }

    function test721FreeMintDeposit(uint256 numTokens) public {
        vm.assume(numTokens > 0 && numTokens < 10_000);

        uint256 totalReward = mockERC721.computeTotalReward(0.000777 ether, numTokens);

        vm.deal(collector, totalReward);

        vm.prank(collector);
        mockERC721.mintWithRewards{value: totalReward}(collector, numTokens, mintReferral);

        IRewardSplits.RewardsSettings memory settings = computeFreeMintRewards(numTokens * 0.000777 ether);

        assertEq(protocolRewards.totalSupply(), totalReward);
        assertEq(protocolRewards.balanceOf(creator), settings.creatorReward);
        assertEq(protocolRewards.balanceOf(createReferral), settings.createReferralReward);
        assertEq(protocolRewards.balanceOf(mintReferral), settings.mintReferralReward);
        assertEq(protocolRewards.balanceOf(collector), settings.firstMinterReward);
        assertEq(protocolRewards.balanceOf(zora), settings.zoraReward);
    }

    function test721PaidMintDeposit(uint256 numTokens, uint256 pricePerToken) public {
        vm.assume(numTokens > 0 && numTokens < 10_000);
        vm.assume(pricePerToken > 0 && pricePerToken < 100 ether);

        mockERC721.setSalePrice(pricePerToken);

        uint256 totalReward = mockERC721.computeTotalReward(0.000777 ether, numTokens);
        uint256 totalSale = numTokens * pricePerToken;
        uint256 totalValue = totalReward + totalSale;

        vm.deal(collector, totalValue);

        vm.prank(collector);
        mockERC721.mintWithRewards{value: totalValue}(collector, numTokens, mintReferral);

        IRewardSplits.RewardsSettings memory settings = computePaidMintRewards(numTokens * 0.000777 ether);

        assertEq(protocolRewards.totalSupply(), totalReward);
        assertEq(protocolRewards.balanceOf(createReferral), settings.createReferralReward);
        assertEq(protocolRewards.balanceOf(mintReferral), settings.mintReferralReward);
        assertEq(protocolRewards.balanceOf(collector), settings.firstMinterReward);
        assertEq(protocolRewards.balanceOf(zora), settings.zoraReward);
    }

    function test721FreeMintNullReferralRecipients() public {
        uint256 numTokens = 1;
        vm.assume(numTokens > 0 && numTokens < 10_000);

        mockERC721 = new MockERC721(creator, address(0), address(protocolRewards), zora);

        uint256 totalReward = mockERC721.computeTotalReward(0.000777 ether, numTokens);

        vm.deal(collector, totalReward);

        vm.prank(collector);
        mockERC721.mintWithRewards{value: totalReward}(collector, numTokens, address(0));

        IRewardSplits.RewardsSettings memory settings = computeFreeMintRewards(0.000777 ether * numTokens);

        assertEq(protocolRewards.totalSupply(), totalReward, "total");
        assertEq(protocolRewards.balanceOf(creator), settings.creatorReward, "creator");
        assertEq(protocolRewards.balanceOf(collector), settings.firstMinterReward, "first minter");
        assertEq(protocolRewards.balanceOf(zora), settings.zoraReward + settings.mintReferralReward + settings.createReferralReward, "zora");
    }

    function test721PaidMintNullReferralRecipient(uint256 numTokens, uint256 pricePerToken) public {
        vm.assume(numTokens > 0 && numTokens < 10_000);
        vm.assume(pricePerToken > 0 && pricePerToken < 100 ether);

        mockERC721 = new MockERC721(creator, address(0), address(protocolRewards), zora);

        mockERC721.setSalePrice(pricePerToken);

        uint256 totalReward = mockERC721.computeTotalReward(0.000777 ether, numTokens);
        uint256 totalSale = numTokens * pricePerToken;
        uint256 totalValue = totalReward + totalSale;

        vm.deal(collector, totalValue);

        vm.prank(collector);
        mockERC721.mintWithRewards{value: totalValue}(collector, numTokens, address(0));

        IRewardSplits.RewardsSettings memory settings = computePaidMintRewards(numTokens * 0.000777 ether);

        assertEq(protocolRewards.totalSupply(), totalReward);
        assertEq(protocolRewards.balanceOf(collector), settings.firstMinterReward);
        assertEq(protocolRewards.balanceOf(zora), settings.zoraReward + settings.mintReferralReward + settings.createReferralReward);
    }

    function testSet721CreatorFundsRecipientAsContractIfNotSet(uint256 numTokens) public {
        vm.assume(numTokens > 0 && numTokens < 10_000);

        mockERC721 = new MockERC721(address(0), createReferral, address(protocolRewards), zora);

        uint256 totalValue = mockERC721.computeTotalReward(0.000777 ether, numTokens);

        IRewardSplits.RewardsSettings memory settings = computeFreeMintRewards(numTokens * 0.000777 ether);

        mockERC721.mintWithRewards{value: totalValue}(collector, numTokens, mintReferral);

        assertEq(protocolRewards.balanceOf(address(mockERC721)), settings.creatorReward);
        assertEq(protocolRewards.balanceOf(collector), settings.firstMinterReward);
    }

    function testRevert721FreeMintInvalidEth(uint256 numTokens) public {
        vm.assume(numTokens > 0 && numTokens < 10_000);

        vm.expectRevert(abi.encodeWithSignature("INVALID_ETH_AMOUNT()"));
        mockERC721.mintWithRewards(collector, numTokens, mintReferral);
    }

    function testRevert721PaidMintInvalidEth(uint256 numTokens, uint256 pricePerToken) public {
        vm.assume(numTokens > 0 && numTokens < 10_000);
        vm.assume(pricePerToken > 0 && pricePerToken < 100 ether);

        mockERC721.setSalePrice(pricePerToken);

        vm.expectRevert(abi.encodeWithSignature("INVALID_ETH_AMOUNT()"));
        mockERC721.mintWithRewards(collector, numTokens, mintReferral);
    }
}
