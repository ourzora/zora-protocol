// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// Extracted interface from Coinbase Smart Wallet's MultiOwnable contract,
/// which we use to check if an address is an owner of the smart wallet
/// in tests without having to include the entire contract in the package
/// Original function can be seen here: https://github.com/coinbase/talaria/blob/main/contracts/src/MultiOwnable.sol
interface IMultiOwnable {
    function isOwnerAddress(address account) external view returns (bool);
}
