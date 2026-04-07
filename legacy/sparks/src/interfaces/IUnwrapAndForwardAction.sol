// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IUnwrapAndForwardAction {
    function callWithEth(address receiverAddress, bytes calldata call, uint256 valueToSend) external payable;
}
