// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface ILegacyNaming {
    function name() external returns (string memory);

    function symbol() external returns (string memory);
}
