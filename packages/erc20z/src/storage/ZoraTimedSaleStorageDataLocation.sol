// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IZoraTimedSaleStrategy} from "../interfaces/IZoraTimedSaleStrategy.sol";

abstract contract ZoraTimedSaleStorageDataLocation {
    /// @dev keccak256(abi.encode(uint256(keccak256("zora.storage.ZoraTimedSaleStrategy")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant ZoraTimedSaleStrategyStorageLocation = 0xe011f00dc6461ce60c6549a992e2b5cccb7ae98ed8fc0ee04eadce4204ebee00;

    /// @notice Returns the storage struct for the Zora Timed Sale Strategy
    function _getZoraTimedSaleStrategyStorage() internal pure returns (IZoraTimedSaleStrategy.ZoraTimedSaleStrategyStorage storage strategyStorage) {
        assembly {
            strategyStorage.slot := ZoraTimedSaleStrategyStorageLocation
        }
    }
}
