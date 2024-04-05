// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IVersionedNamedContract {
    function contractName() external returns (string memory);
    function contractVersion() external returns (string memory);
}
