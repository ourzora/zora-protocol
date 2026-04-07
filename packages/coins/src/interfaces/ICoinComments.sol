// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ICoinComments {
    function isOwner(address) external view returns (bool);
    function payoutRecipient() external view returns (address);
    function balanceOf(address) external view returns (uint256);
}
