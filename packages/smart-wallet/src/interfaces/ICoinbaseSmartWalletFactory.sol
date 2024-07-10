// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ICoinbaseSmartWallet} from "./ICoinbaseSmartWallet.sol";

interface ICoinbaseSmartWalletFactory {
    function createAccount(bytes[] calldata owners, uint256 nonce) external returns (ICoinbaseSmartWallet account);

    function getAddress(bytes[] calldata owners, uint256 nonce) external view returns (address);

    function initCodeHash() external view returns (bytes32);

    function implementation() external view returns (address);
}
