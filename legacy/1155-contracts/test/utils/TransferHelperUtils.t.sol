// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {Test} from "forge-std/Test.sol";
import {TransferHelperUtils} from "../../src/utils/TransferHelperUtils.sol";

contract BadReceiver {
    uint256 public gasUsed;

    function setGasUsed(uint256 _gasUsed) external {
        gasUsed = _gasUsed;
    }

    event OK(uint256);

    receive() external payable {
        uint256 startGas = gasleft();
        uint256 gasLeft = startGas;
        uint256 whatever;
        while (gasLeft > startGas - gasUsed) {
            unchecked {
                whatever++;
            }
            gasLeft = gasleft();
            emit OK(gasLeft);
        }
    }
}

contract FundsSender {
    function lowGasLimit() external view returns (uint256) {
        return TransferHelperUtils.FUNDS_SEND_LOW_GAS_LIMIT;
    }

    function normalGasLimit() external view returns (uint256) {
        return TransferHelperUtils.FUNDS_SEND_NORMAL_GAS_LIMIT;
    }

    function safeSendETH(address recipient, uint256 value, uint256 limit) external returns (bool) {
        return TransferHelperUtils.safeSendETH(recipient, value, limit);
    }
}

contract TransferHelperUtilsTest is Test {
    FundsSender sender = new FundsSender();

    function test_TransferHighGasLimitSucceeds() public {
        vm.deal(address(sender), 1 ether);
        address recipient1 = address(0x99942);
        sender.safeSendETH(recipient1, 1 ether, sender.normalGasLimit());
        assertEq(address(recipient1).balance, 1 ether);
    }

    function test_TransferLowGasLimitSucceeds() public {
        vm.deal(address(sender), 1 ether);
        address recipient1 = address(0x99000);
        sender.safeSendETH(recipient1, 1 ether, sender.lowGasLimit());
        assertEq(address(recipient1).balance, 1 ether);
    }

    function test_TransferLowGasLimitFailsNoMoreGas() public {
        BadReceiver bad = new BadReceiver();
        bad.setGasUsed(400_000);
        vm.deal(address(sender), 1 ether);
        assertEq(sender.safeSendETH(address(bad), 1 ether, sender.lowGasLimit()), false);
        assertEq(address(sender).balance, 1 ether);
    }

    function test_TransferHighGasLimitFailsNoMoreGas() public {
        BadReceiver bad = new BadReceiver();
        bad.setGasUsed(500_000);
        vm.deal(address(sender), 1 ether);
        assertEq(sender.safeSendETH(address(bad), 1 ether, sender.normalGasLimit()), false);
        assertEq(address(sender).balance, 1 ether);
    }

    function test_TransferLowGasLimitSucceedsGasLimitOk() public {
        BadReceiver bad = new BadReceiver();
        bad.setGasUsed(55_000);
        vm.deal(address(sender), 1 ether);
        assertEq(sender.safeSendETH(address(bad), 1 ether, sender.lowGasLimit()), true);
        assertEq(address(sender).balance, 0 ether);
        assertEq(address(bad).balance, 1 ether);
    }

    function test_TransferHighGasLimitSucceedsGasLimitOk() public {
        BadReceiver bad = new BadReceiver();
        bad.setGasUsed(255_000);
        vm.deal(address(sender), 1 ether);
        assertEq(sender.safeSendETH(address(bad), 1 ether, sender.normalGasLimit()), true);
        assertEq(address(sender).balance, 0 ether);
        assertEq(address(bad).balance, 1 ether);
    }
}
