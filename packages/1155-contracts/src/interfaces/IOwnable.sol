// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IOwnable {
    function owner() external returns (address);

    event OwnershipTransferred(address lastOwner, address newOwner);
}
