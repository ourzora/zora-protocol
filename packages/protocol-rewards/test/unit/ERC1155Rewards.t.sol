// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "../ProtocolRewardsTest.sol";
import {RewardsSettings} from "../../src/abstract/RewardSplits.sol";

contract ERC1155RewardsTest is ProtocolRewardsTest {
    MockERC1155 internal mockERC1155;

    function setUp() public override {
        super.setUp();

        mockERC1155 = new MockERC1155(creator, createReferral, address(protocolRewards), zora);

        vm.label(address(mockERC1155), "MOCK_ERC1155");
    }

    function test1155FreeMintDeposit(uint16 numTokens) public {
        vm.assume(numTokens > 0);

        uint256 totalReward = mockERC1155.computeTotalReward(numTokens);

        vm.deal(collector, totalReward);

        vm.prank(collector);
        mockERC1155.mintWithRewards{value: totalReward}(collector, 0, numTokens, mintReferral);

        RewardsSettings memory settings = mockERC1155.computeFreeMintRewards(numTokens);

        assertEq(protocolRewards.totalSupply(), totalReward);
        assertEq(protocolRewards.balanceOf(creator), settings.creatorReward);
        assertEq(protocolRewards.balanceOf(createReferral), settings.createReferralReward);
        assertEq(protocolRewards.balanceOf(mintReferral), settings.mintReferralReward);
        assertEq(protocolRewards.balanceOf(collector), settings.firstMinterReward);
        assertEq(protocolRewards.balanceOf(zora), settings.zoraReward);
    }

    function test1155PaidMintDeposit(uint16 numTokens, uint256 pricePerToken) public {
        vm.assume(numTokens > 0);
        vm.assume(pricePerToken > 0 && pricePerToken < 100 ether);

        mockERC1155.setSalePrice(pricePerToken);

        uint256 totalReward = mockERC1155.computeTotalReward(numTokens);
        uint256 totalSale = numTokens * pricePerToken;
        uint256 totalValue = totalReward + totalSale;

        vm.deal(collector, totalValue);

        vm.prank(collector);
        mockERC1155.mintWithRewards{value: totalValue}(collector, 0, numTokens, mintReferral);

        RewardsSettings memory settings = mockERC1155.computePaidMintRewards(numTokens);

        assertEq(protocolRewards.totalSupply(), totalReward);
        assertEq(protocolRewards.balanceOf(createReferral), settings.createReferralReward);
        assertEq(protocolRewards.balanceOf(mintReferral), settings.mintReferralReward);
        assertEq(protocolRewards.balanceOf(collector), settings.firstMinterReward);
        assertEq(protocolRewards.balanceOf(zora), settings.zoraReward);
    }

    function test1155FreeMintNullReferralRecipients(uint16 numTokens) public {
        vm.assume(numTokens > 0);

        mockERC1155 = new MockERC1155(creator, address(0), address(protocolRewards), zora);

        uint256 totalReward = mockERC1155.computeTotalReward(numTokens);

        vm.deal(collector, totalReward);

        vm.prank(collector);
        mockERC1155.mintWithRewards{value: totalReward}(collector, 0, numTokens, address(0));

        RewardsSettings memory settings = mockERC1155.computeFreeMintRewards(numTokens);

        assertEq(protocolRewards.totalSupply(), totalReward);
        assertEq(protocolRewards.balanceOf(creator), settings.creatorReward);
        assertEq(protocolRewards.balanceOf(collector), settings.firstMinterReward);
        assertEq(protocolRewards.balanceOf(zora), settings.zoraReward + settings.mintReferralReward + settings.createReferralReward);
    }

    function test1155PaidMintNullReferralRecipient(uint16 numTokens, uint256 pricePerToken) public {
        vm.assume(numTokens > 0);
        vm.assume(pricePerToken > 0 && pricePerToken < 100 ether);

        mockERC1155 = new MockERC1155(creator, address(0), address(protocolRewards), zora);

        mockERC1155.setSalePrice(pricePerToken);

        uint256 totalReward = mockERC1155.computeTotalReward(numTokens);
        uint256 totalSale = numTokens * pricePerToken;
        uint256 totalValue = totalReward + totalSale;

        vm.deal(collector, totalValue);

        vm.prank(collector);
        mockERC1155.mintWithRewards{value: totalValue}(collector, 0, numTokens, address(0));

        RewardsSettings memory settings = mockERC1155.computePaidMintRewards(numTokens);

        assertEq(protocolRewards.totalSupply(), totalReward);
        assertEq(protocolRewards.balanceOf(collector), settings.firstMinterReward);
        assertEq(protocolRewards.balanceOf(zora), settings.zoraReward + settings.mintReferralReward + settings.createReferralReward);
    }

    function testRevert1155FreeMintInvalidEth(uint16 numTokens) public {
        vm.assume(numTokens > 0);

        vm.expectRevert(abi.encodeWithSignature("INVALID_ETH_AMOUNT()"));
        mockERC1155.mintWithRewards(collector, 0, numTokens, mintReferral);
    }

    function testRevert1155PaidMintInvalidEth(uint16 numTokens, uint256 pricePerToken) public {
        vm.assume(numTokens > 0);
        vm.assume(pricePerToken > 0 && pricePerToken < 100 ether);

        mockERC1155.setSalePrice(pricePerToken);

        vm.expectRevert(abi.encodeWithSignature("INVALID_ETH_AMOUNT()"));
        mockERC1155.mintWithRewards(collector, 0, numTokens, mintReferral);
    }

    function testRevert1155PaidMintInvalidEthRemaining(uint16 numTokens, uint256 pricePerToken) public {
        vm.assume(numTokens > 0);
        vm.assume(pricePerToken > 0 && pricePerToken < 100 ether);

        mockERC1155.setSalePrice(pricePerToken);

        uint256 totalReward = mockERC1155.computeTotalReward(numTokens);
        uint256 totalSale = numTokens * pricePerToken;
        uint256 totalValue = totalReward + totalSale;

        vm.deal(collector, totalValue);

        vm.prank(collector);
        vm.expectRevert(abi.encodeWithSignature("MOCK_ERC1155_INVALID_REMAINING_VALUE()"));
        mockERC1155.mintWithRewards{value: totalValue - 1}(collector, 0, numTokens, mintReferral);
    }
}
