// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IEntryPoint {
    function getNonce(address sender, uint192 key) external view returns (uint256);
}
