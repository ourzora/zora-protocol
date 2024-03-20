// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

contract ReceiveRejector {
    receive() external payable {
        revert("Transfer rejected");
    }
}
