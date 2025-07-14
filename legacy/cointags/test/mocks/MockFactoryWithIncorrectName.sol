// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IHasContractName} from "@zoralabs/shared-contracts/interfaces/IContractMetadata.sol";

contract MockFactoryWithIncorrectName is IHasContractName {
    function contractName() public pure override returns (string memory) {
        return "Different Name";
    }
}
