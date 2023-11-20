// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

contract ZoraAccount is Experience, ERC1967Proxy {
    constructor(address _logic, bytes memory _init) ERC1967Proxy(_logic, _init) {}
}