// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IVersionedContract} from "../interfaces/IVersionedContract.sol";

contract ContractVersionBase is IVersionedContract {
    function contractVersion() external pure override returns (string memory) {
        return "0.0.6";
    }
}
