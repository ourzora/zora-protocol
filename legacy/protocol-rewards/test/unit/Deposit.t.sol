// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "../ProtocolRewardsTest.sol";
import "../../src/abstract/RewardSplits.sol";

contract DepositTest is ProtocolRewardsTest {
    function setUp() public override {
        super.setUp();
    }

    function testDeposit(uint256 amount, address to) public {
        vm.assume(amount < ETH_SUPPLY);
        vm.assume(to != address(0));

        vm.deal(collector, amount);

        vm.prank(collector);
        protocolRewards.deposit{value: amount}(to, bytes4(0), "test");

        assertEq(protocolRewards.balanceOf(to), amount);
    }

    function testRevert_CannotDepositToAddressZero(uint256 amount) public {
        vm.assume(amount < ETH_SUPPLY);

        vm.deal(collector, amount);

        vm.prank(collector);
        vm.expectRevert(abi.encodeWithSignature("ADDRESS_ZERO()"));
        protocolRewards.deposit{value: amount}(address(0), bytes4(0), "test");
    }

    function testDepositBatch(uint8 numRecipients) public {
        address[] memory recipients = new address[](numRecipients);
        uint256[] memory amounts = new uint256[](numRecipients);
        bytes4[] memory reasons = new bytes4[](numRecipients);

        uint256 totalValue;

        for (uint256 i; i < numRecipients; ++i) {
            recipients[i] = makeAddr(vm.toString(i + 1));
            amounts[i] = i + 1 ether;

            totalValue += amounts[i];
        }

        vm.deal(collector, totalValue);
        vm.prank(collector);
        protocolRewards.depositBatch{value: totalValue}(recipients, amounts, reasons, "test");

        for (uint256 i; i < numRecipients; ++i) {
            assertEq(protocolRewards.balanceOf(recipients[i]), amounts[i]);
        }
    }

    function testRevert_RecipientsAndAmountsLengthMismatch(uint8 numRecipients, uint8 numAmounts) public {
        vm.assume(numRecipients != numAmounts);

        address[] memory recipients = new address[](numRecipients);
        uint256[] memory amounts = new uint256[](numAmounts);
        bytes4[] memory reasons = new bytes4[](numAmounts);

        uint256 totalValue;

        for (uint256 i; i < numAmounts; ++i) {
            amounts[i] = i + 1 ether;

            totalValue += amounts[i];
        }

        for (uint256 i; i < numRecipients; ++i) {
            recipients[i] = makeAddr(vm.toString(i + 1));
        }

        vm.deal(collector, totalValue);

        vm.prank(collector);
        vm.expectRevert(abi.encodeWithSignature("ARRAY_LENGTH_MISMATCH()"));
        protocolRewards.depositBatch{value: totalValue}(recipients, amounts, reasons, "test");
    }

    function testRevert_InvalidDepositMsgValue(uint8 numRecipients) public {
        vm.assume(numRecipients > 0);

        address[] memory recipients = new address[](numRecipients);
        uint256[] memory amounts = new uint256[](numRecipients);
        bytes4[] memory reasons = new bytes4[](numRecipients);

        uint256 totalValue;

        for (uint256 i; i < numRecipients; ++i) {
            recipients[i] = makeAddr(vm.toString(i + 1));
            amounts[i] = i + 1 ether;

            totalValue += amounts[i];
        }

        vm.deal(collector, totalValue);

        vm.prank(collector);
        vm.expectRevert(abi.encodeWithSignature("INVALID_DEPOSIT()"));
        protocolRewards.depositBatch{value: 0}(recipients, amounts, reasons, "test");
    }

    function testRevert_RecipientCannotBeAddressZero(uint8 numRecipients) public {
        vm.assume(numRecipients > 0);

        address[] memory recipients = new address[](numRecipients);
        uint256[] memory amounts = new uint256[](numRecipients);
        bytes4[] memory reasons = new bytes4[](numRecipients);

        uint256 totalValue;

        for (uint256 i; i < numRecipients; ++i) {
            recipients[i] = makeAddr(vm.toString(i + 1));
            amounts[i] = i + 1 ether;

            totalValue += amounts[i];
        }

        recipients[0] = address(0);

        vm.deal(collector, totalValue);

        vm.prank(collector);
        vm.expectRevert(abi.encodeWithSignature("ADDRESS_ZERO()"));
        protocolRewards.depositBatch{value: totalValue}(recipients, amounts, reasons, "test");
    }
}
