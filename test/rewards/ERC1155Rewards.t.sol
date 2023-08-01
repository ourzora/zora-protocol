// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {ERC1155Rewards, ERC1155RewardsStorage} from "../../src/rewards/ERC1155Rewards.sol";
import {ProtocolRewards} from "@zoralabs/protocol-rewards/dist/contracts/ProtocolRewards.sol";

contract MockERC1155 is ERC1155, ERC1155Rewards, ERC1155RewardsStorage {
    error MOCK_ERC1155_INVALID_REMAINING_VALUE();

    address public creator;
    uint256 public salePrice;

    constructor(
        address _creator,
        address _createReferral,
        address _protocolRewards,
        address _zoraRewardRecipient
    ) ERC1155("Mock ERC1155 URI") ERC1155Rewards(_protocolRewards, _zoraRewardRecipient) {
        creator = _creator;
        createReferrals[0] = _createReferral;
    }

    function setSalePrice(uint256 _salePrice) external {
        salePrice = _salePrice;
    }

    function mintWithRewards(address to, uint256 tokenId, uint256 numTokens, address mintReferral) external payable {
        uint256 remainingValue = _handleRewardsAndGetValueSent(msg.value, numTokens, creator, mintReferral, createReferrals[tokenId]);

        uint256 expectedRemainingValue = salePrice * numTokens;

        if (remainingValue != expectedRemainingValue) revert MOCK_ERC1155_INVALID_REMAINING_VALUE();

        _mint(to, tokenId, numTokens, "");
    }
}

contract ERC1155RewardsTest is Test {
    MockERC1155 internal mockERC1155;
    ProtocolRewards internal protocolRewards;

    address internal collector;
    address internal creator;
    address internal mintReferral;
    address internal createReferral;
    address internal zora;

    function setUp() public {
        protocolRewards = new ProtocolRewards();

        vm.label(address(protocolRewards), "protocolRewards");

        collector = makeAddr("collector");
        creator = makeAddr("creator");
        mintReferral = makeAddr("mintReferral");
        createReferral = makeAddr("createReferral");
        zora = makeAddr("zora");

        mockERC1155 = new MockERC1155(creator, createReferral, address(protocolRewards), zora);

        vm.label(address(mockERC1155), "MOCK_ERC1155");
    }

    function test1155FreeMintDeposit(uint16 numTokens) public {
        vm.assume(numTokens > 0);

        uint256 totalReward = mockERC1155.computeTotalReward(numTokens);

        vm.deal(collector, totalReward);

        vm.prank(collector);
        mockERC1155.mintWithRewards{value: totalReward}(collector, 0, numTokens, mintReferral);

        (uint256 creatorReward, uint256 mintReferralReward, uint256 createReferralReward, uint256 firstMinterReward, uint256 zoraReward) = mockERC1155
            .computeFreeMintRewards(numTokens);

        assertEq(protocolRewards.totalSupply(), totalReward);
        assertEq(protocolRewards.balanceOf(creator), creatorReward + firstMinterReward);
        assertEq(protocolRewards.balanceOf(mintReferral), mintReferralReward);
        assertEq(protocolRewards.balanceOf(createReferral), createReferralReward);
        assertEq(protocolRewards.balanceOf(zora), zoraReward);
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

        (uint256 mintReferralReward, uint256 createReferralReward, uint256 firstMinterReward, uint256 zoraReward) = mockERC1155.computePaidMintRewards(
            numTokens
        );

        assertEq(protocolRewards.totalSupply(), totalReward);
        assertEq(protocolRewards.balanceOf(creator), firstMinterReward);
        assertEq(protocolRewards.balanceOf(mintReferral), mintReferralReward);
        assertEq(protocolRewards.balanceOf(createReferral), createReferralReward);
        assertEq(protocolRewards.balanceOf(zora), zoraReward);
    }

    function test1155FreeMintNullReferralRecipients(uint16 numTokens) public {
        vm.assume(numTokens > 0);

        mockERC1155 = new MockERC1155(creator, address(0), address(protocolRewards), zora);

        uint256 totalReward = mockERC1155.computeTotalReward(numTokens);

        vm.deal(collector, totalReward);

        vm.prank(collector);
        mockERC1155.mintWithRewards{value: totalReward}(collector, 0, numTokens, address(0));

        (uint256 creatorReward, uint256 mintReferralReward, uint256 createReferralReward, uint256 firstMinterReward, uint256 zoraReward) = mockERC1155
            .computeFreeMintRewards(numTokens);

        assertEq(protocolRewards.totalSupply(), totalReward);
        assertEq(protocolRewards.balanceOf(creator), creatorReward + firstMinterReward);
        assertEq(protocolRewards.balanceOf(zora), zoraReward + mintReferralReward + createReferralReward);
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

        (uint256 mintReferralReward, uint256 createReferralReward, uint256 firstMinterReward, uint256 zoraReward) = mockERC1155.computePaidMintRewards(
            numTokens
        );

        assertEq(protocolRewards.totalSupply(), totalReward);
        assertEq(protocolRewards.balanceOf(creator), firstMinterReward);
        assertEq(protocolRewards.balanceOf(zora), zoraReward + mintReferralReward + createReferralReward);
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
