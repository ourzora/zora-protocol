// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Enjoy} from "_imagine/Enjoy.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @title Cointag Proxy Contract
/// @notice This is the proxy contract for the Cointag contracts
/// @dev Inherits from ERC1967Proxy to enable upgradeable functionality.
contract Cointag is Enjoy, ERC1967Proxy {
    bytes32 internal immutable name;

    constructor(address _logic, bytes memory _data) ERC1967Proxy(_logic, _data) {
        // added to create unique bytecode for this contract
        // so that it can be properly verified as its own contract.
        name = keccak256("Cointag");
    }
}
