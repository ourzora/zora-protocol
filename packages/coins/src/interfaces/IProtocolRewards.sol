// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IProtocolRewards {
    function balanceOf(address account) external view returns (uint256);

    function deposit(address to, bytes4 why, string calldata comment) external payable;

    function depositBatch(address[] calldata recipients, uint256[] calldata amounts, bytes4[] calldata reasons, string calldata comment) external payable;

    function withdrawFor(address to, uint256 amount) external;
}
