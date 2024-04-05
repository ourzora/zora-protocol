// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {ILegacyNaming} from "@zoralabs/shared-contracts/interfaces/ILegacyNaming.sol";
import {LegacyNamingStorageV1} from "./LegacyNamingStorageV1.sol";

/// @title LegacyNamingControl
/// @notice Contract for managing the name and symbol of an 1155 contract in the legacy naming scheme
contract LegacyNamingControl is LegacyNamingStorageV1, ILegacyNaming {
    /// @notice The name of the contract
    function name() external view returns (string memory) {
        return _name;
    }

    /// @notice The token symbol of the contract
    function symbol() external pure returns (string memory) {}

    function _setName(string memory _newName) internal {
        _name = _newName;
    }
}
