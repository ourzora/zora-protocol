// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {ILegacyNaming} from "../interfaces/ILegacyNaming.sol";
import {LegacyNamingStorageV1} from "./LegacyNamingStorageV1.sol";

contract LegacyNamingControl is LegacyNamingStorageV1, ILegacyNaming {
    function name() external view returns (string memory) {
        return _name;
    }

    function symbol() external pure returns (string memory) {}

    function _setName(string memory _newName) internal {
        _name = _newName;
    }
}
