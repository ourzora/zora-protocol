// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "../ProtocolRewardsTest.sol";
import {IRewardSplits} from "../../src/interfaces/IRewardSplits.sol";
import {RewardSplitsLib} from "../../src/abstract/RewardSplits.sol";

contract ERC1155RewardsTest is ProtocolRewardsTest {
    MockERC1155 internal mockERC1155;

    function setUp() public override {
        super.setUp();

        mockERC1155 = new MockERC1155(creator, createReferral, address(protocolRewards), zora);

        vm.label(address(mockERC1155), "MOCK_ERC1155");
    }

    function computeFreeMintRewards(uint256 value) private pure returns (IRewardSplits.RewardsSettings memory) {
        return RewardSplitsLib.getRewards(false, value);
    }

    function computePaidMintRewards(uint256 value) private pure returns (IRewardSplits.RewardsSettings memory) {
        return RewardSplitsLib.getRewards(true, value);
    }

    function test1155FreeMintDeposit(uint256 numTokens) public {
        vm.assume(numTokens > 0 && numTokens < 100_000);

        uint256 totalReward = mockERC1155.computeTotalReward(0.000777 ether, numTokens);

        vm.deal(collector, totalReward);

        vm.prank(collector);
        mockERC1155.mintWithRewards{value: totalReward}(collector, 0, numTokens, mintReferral, 0.000777 ether);

        IRewardSplits.RewardsSettings memory settings = computeFreeMintRewards(numTokens * 0.000777 ether);

        assertEq(protocolRewards.totalSupply(), totalReward);
        assertEq(protocolRewards.balanceOf(creator), settings.creatorReward);
        assertEq(protocolRewards.balanceOf(createReferral), settings.createReferralReward);
        assertEq(protocolRewards.balanceOf(mintReferral), settings.mintReferralReward);
        assertEq(protocolRewards.balanceOf(collector), settings.firstMinterReward);
        assertEq(protocolRewards.balanceOf(zora), settings.zoraReward);
    }

    function test1155PaidMintDeposit(uint256 numTokens, uint256 pricePerToken) public {
        vm.assume(numTokens > 0 && numTokens < 100_000);
        vm.assume(pricePerToken > 0 && pricePerToken < 100 ether);

        mockERC1155.setSalePrice(pricePerToken);

        uint256 totalReward = mockERC1155.computeTotalReward(0.000777 ether, numTokens);
        uint256 totalSale = numTokens * pricePerToken;
        uint256 totalValue = totalReward + totalSale;

        vm.deal(collector, totalValue);

        vm.prank(collector);
        mockERC1155.mintWithRewards{value: totalValue}(collector, 0, numTokens, mintReferral, 0.000777 ether);

        IRewardSplits.RewardsSettings memory settings = computePaidMintRewards(numTokens * 0.000777 ether);

        assertEq(protocolRewards.totalSupply(), totalReward);
        assertEq(protocolRewards.balanceOf(createReferral), settings.createReferralReward);
        assertEq(protocolRewards.balanceOf(mintReferral), settings.mintReferralReward);
        assertEq(protocolRewards.balanceOf(collector), settings.firstMinterReward);
        assertEq(protocolRewards.balanceOf(zora), settings.zoraReward);
    }

    function test1155FreeMintNullReferralRecipients(uint256 numTokens) public {
        vm.assume(numTokens > 0 && numTokens < 100_000);

        mockERC1155 = new MockERC1155(creator, address(0), address(protocolRewards), zora);

        uint256 totalReward = mockERC1155.computeTotalReward(0.000777 ether, numTokens);

        vm.deal(collector, totalReward);

        vm.prank(collector);
        mockERC1155.mintWithRewards{value: totalReward}(collector, 0, numTokens, address(0), 0.000777 ether);

        IRewardSplits.RewardsSettings memory settings = computeFreeMintRewards(numTokens * 0.000777 ether);

        assertEq(protocolRewards.totalSupply(), totalReward);
        assertEq(protocolRewards.balanceOf(creator), settings.creatorReward);
        assertEq(protocolRewards.balanceOf(collector), settings.firstMinterReward);
        assertEq(protocolRewards.balanceOf(zora), settings.zoraReward + settings.mintReferralReward + settings.createReferralReward);
    }

    function test1155PaidMintNullReferralRecipient(uint256 numTokens, uint256 pricePerToken) public {
        vm.assume(numTokens > 0 && numTokens < 100_000);
        vm.assume(pricePerToken > 0 && pricePerToken < 100 ether);

        mockERC1155 = new MockERC1155(creator, address(0), address(protocolRewards), zora);

        mockERC1155.setSalePrice(pricePerToken);

        uint256 totalReward = mockERC1155.computeTotalReward(0.000777 ether, numTokens);
        uint256 totalSale = numTokens * pricePerToken;
        uint256 totalValue = totalReward + totalSale;

        vm.deal(collector, totalValue);

        vm.prank(collector);
        mockERC1155.mintWithRewards{value: totalValue}(collector, 0, numTokens, address(0), 0.000777 ether);

        IRewardSplits.RewardsSettings memory settings = computePaidMintRewards(numTokens * 0.000777 ether);

        assertEq(protocolRewards.totalSupply(), totalReward);
        assertEq(protocolRewards.balanceOf(collector), settings.firstMinterReward);
        assertEq(protocolRewards.balanceOf(zora), settings.zoraReward + settings.mintReferralReward + settings.createReferralReward);
    }

    function testRevert1155FreeMintInvalidEth(uint256 numTokens) public {
        vm.assume(numTokens > 0 && numTokens < 100_000);

        vm.expectRevert(abi.encodeWithSignature("INVALID_ETH_AMOUNT()"));
        mockERC1155.mintWithRewards(collector, 0, numTokens, mintReferral, 0.000777 ether);
    }

    function testRevert1155PaidMintInvalidEth(uint256 numTokens, uint256 pricePerToken) public {
        vm.assume(numTokens > 0 && numTokens < 100_000);
        vm.assume(pricePerToken > 0 && pricePerToken < 100 ether);

        mockERC1155.setSalePrice(pricePerToken);

        vm.expectRevert(abi.encodeWithSignature("INVALID_ETH_AMOUNT()"));
        mockERC1155.mintWithRewards(collector, 0, numTokens, mintReferral, 0.000777 ether);
    }

    function testRevert1155PaidMintInvalidEthRemaining(uint256 numTokens, uint256 pricePerToken) public {
        vm.assume(numTokens > 0 && numTokens < 100_000);
        vm.assume(pricePerToken > 0 && pricePerToken < 100 ether);

        mockERC1155.setSalePrice(pricePerToken);

        uint256 totalReward = mockERC1155.computeTotalReward(0.000777 ether, numTokens);
        uint256 totalSale = numTokens * pricePerToken;
        uint256 totalValue = totalReward + totalSale;

        vm.deal(collector, totalValue);

        vm.prank(collector);
        vm.expectRevert(abi.encodeWithSignature("MOCK_ERC1155_INVALID_REMAINING_VALUE()"));
        mockERC1155.mintWithRewards{value: totalValue - 1}(collector, 0, numTokens, mintReferral, 0.000777 ether);
    }

    function testRemainderSentToZora(uint256 rewardPrice, uint256 numTokens) public {
        vm.assume(rewardPrice > 0.0000002 ether && rewardPrice < 100 ether);
        vm.assume(numTokens > 0 && numTokens < 100_000);

        uint256 totalReward = mockERC1155.computeTotalReward(rewardPrice, numTokens);

        vm.deal(collector, totalReward);
        vm.prank(collector);
        mockERC1155.mintWithRewards{value: totalReward}(collector, 0, numTokens, mintReferral, rewardPrice);

        IRewardSplits.RewardsSettings memory settings = computeFreeMintRewards(numTokens * rewardPrice);

        assertEq(protocolRewards.totalSupply(), totalReward);
        assertEq(protocolRewards.balanceOf(creator), settings.creatorReward);
        assertEq(protocolRewards.balanceOf(createReferral), settings.createReferralReward);
        assertEq(protocolRewards.balanceOf(mintReferral), settings.mintReferralReward);
        assertEq(protocolRewards.balanceOf(collector), settings.firstMinterReward);
        assertEq(protocolRewards.balanceOf(zora), settings.zoraReward);
        assertEq(
            protocolRewards.balanceOf(zora),
            totalReward - (settings.creatorReward + settings.createReferralReward + settings.mintReferralReward + settings.firstMinterReward)
        );
    }

    function testRemainderSentToZoraPaidMint(uint128 rewardPrice, uint256 numTokens, uint256 tokenPrice) public {
        vm.assume(rewardPrice > 0.0000002 ether && rewardPrice < 100 ether);
        vm.assume(tokenPrice > 0 ether && tokenPrice < 5 ether);
        vm.assume(numTokens > 0 && numTokens < 100_000);

        uint256 totalReward = mockERC1155.computeTotalReward(rewardPrice, numTokens);
        uint256 totalValue = totalReward + (numTokens * tokenPrice);

        vm.deal(collector, totalValue);
        vm.prank(collector);
        mockERC1155.setSalePrice(tokenPrice);
        mockERC1155.mintWithRewards{value: totalValue}(collector, 0, numTokens, mintReferral, rewardPrice);

        IRewardSplits.RewardsSettings memory settings = computePaidMintRewards(numTokens * rewardPrice);

        assertEq(protocolRewards.totalSupply(), totalReward);
        assertEq(protocolRewards.balanceOf(creator), settings.creatorReward);
        assertEq(protocolRewards.balanceOf(createReferral), settings.createReferralReward);
        assertEq(protocolRewards.balanceOf(mintReferral), settings.mintReferralReward);
        assertEq(protocolRewards.balanceOf(collector), settings.firstMinterReward);
        assertEq(protocolRewards.balanceOf(zora), settings.zoraReward);
        assertEq(
            protocolRewards.balanceOf(zora),
            totalReward - (settings.creatorReward + settings.createReferralReward + settings.mintReferralReward + settings.firstMinterReward)
        );
    }

    function testRewardCalculationIsCorrectFreeMint() public {
        // assume that the reward price is 0.000777 ether and the number of tokens is 1
        uint256 rewardPrice = 0.000777 ether;
        uint256 numTokens = 1;
        uint256 totalReward = mockERC1155.computeTotalReward(rewardPrice, numTokens);
        uint256 totalValue = totalReward + numTokens;

        vm.deal(collector, totalValue);
        vm.prank(collector);

        IRewardSplits.RewardsSettings memory settings = computeFreeMintRewards(numTokens * rewardPrice);

        assertApproxEqRel(settings.creatorReward, 0.000333 ether, 0.01e18);
        assertApproxEqRel(settings.createReferralReward, 0.000111 ether, 0.01e18);
        assertApproxEqRel(settings.mintReferralReward, 0.000111 ether, 0.01e18);
        assertApproxEqRel(settings.firstMinterReward, 0.000111 ether, 0.01e18);
        // ZoraReward will be greater than 0.000111 ether as it also includes the remainder
        assertGe(settings.zoraReward, 0.000111 ether);
    }

    function testRewardCalculationIsCorrectFreeMintFuzzy(uint256 numTokens, uint256 rewardPrice) public {
        vm.assume(rewardPrice > 0.0000002 ether && rewardPrice < 10 ether);
        vm.assume(numTokens > 0 && numTokens < 1_000_000);

        uint256 totalReward = mockERC1155.computeTotalReward(rewardPrice, numTokens);
        uint256 totalValue = totalReward + numTokens;

        vm.deal(collector, totalValue);
        vm.prank(collector);

        IRewardSplits.RewardsSettings memory settings = computeFreeMintRewards(numTokens * rewardPrice);

        assertApproxEqRel(settings.creatorReward, (42_857100 * totalReward) / 10_0000000, 0.01e18);
        assertApproxEqRel(settings.createReferralReward, (14_228500 * totalReward) / 10_0000000, 0.01e18);
        assertApproxEqRel(settings.mintReferralReward, (14_228500 * totalReward) / 10_0000000, 0.01e18);
        assertApproxEqRel(settings.firstMinterReward, (14_228500 * totalReward) / 10_0000000, 0.01e18);
        assertGe(settings.zoraReward, (14_228500 * totalReward) / 10_0000000);
    }

    function testRewardCalculationIsCorrectPaidMint() public {
        // assume that the reward price is 0.000777 ether and the number of tokens is 1
        uint256 rewardPrice = 0.000777 ether;
        uint256 numTokens = 1;
        uint256 totalReward = mockERC1155.computeTotalReward(rewardPrice, numTokens);
        uint256 totalValue = totalReward + numTokens;

        vm.deal(collector, totalValue);
        vm.prank(collector);

        IRewardSplits.RewardsSettings memory settings = computePaidMintRewards(numTokens * rewardPrice);

        assertApproxEqRel(settings.creatorReward, 0 ether, 0.01e18);
        assertApproxEqRel(settings.createReferralReward, 0.000222 ether, 0.01e18);
        assertApproxEqRel(settings.mintReferralReward, 0.000222 ether, 0.01e18);
        assertApproxEqRel(settings.firstMinterReward, 0.000111 ether, 0.01e18);
        // ZoraReward will be greater than 0.000222 ether as it also includes the remainder
        assertGe(settings.zoraReward, 0.000222 ether);
    }

    function testRewardCalculationIsCorrectPaidMintFuzzy(uint256 numTokens) public {
        vm.assume(numTokens > 0 && numTokens < 1_000_000);

        uint256 rewardPrice = 0.000777 ether;
        uint256 totalReward = mockERC1155.computeTotalReward(rewardPrice, numTokens);
        uint256 totalValue = totalReward + numTokens;

        vm.deal(collector, totalValue);
        vm.prank(collector);

        IRewardSplits.RewardsSettings memory settings = computePaidMintRewards(numTokens * rewardPrice);

        assertEq(settings.creatorReward, 0);
        assertApproxEqRel(settings.createReferralReward, (28_571400 * totalReward) / 10_0000000, 0.01e18);
        assertApproxEqRel(settings.mintReferralReward, (28_571400 * totalReward) / 10_0000000, 0.01e18);
        assertApproxEqRel(settings.firstMinterReward, (14_228500 * totalReward) / 10_0000000, 0.01e18);
        assertGe(settings.zoraReward, (28_571400 * totalReward) / 10_0000000);
    }
}
