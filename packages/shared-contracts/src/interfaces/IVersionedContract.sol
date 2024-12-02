// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

interface IVersionedContract {
    function contractVersion() external pure returns (string memory);
}
