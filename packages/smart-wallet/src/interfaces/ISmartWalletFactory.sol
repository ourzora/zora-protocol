// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface ISmartWalletFactory {
    function createAccount(bytes[] calldata owners, uint256 nonce) external;
    function getAddress(bytes[] calldata owners, uint256 nonce) external view returns (address);

    function initCodeHash() external view returns (bytes32);
    function implementation() external view returns (address);
}
