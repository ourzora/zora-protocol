// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IHasContractName} from "@zoralabs/shared-contracts/interfaces/IContractMetadata.sol";

contract MockContractWithName is IHasContractName {
    string private name;

    constructor(string memory _name) {
        name = _name;
    }

    function contractName() public view override returns (string memory) {
        return name;
    }
}
