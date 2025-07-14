// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IZoraTimedSaleStrategy} from "../interfaces/IZoraTimedSaleStrategy.sol";

abstract contract ZoraTimedSaleStorageDataLocation {
    /// @dev keccak256(abi.encode(uint256(keccak256("zora.storage.ZoraTimedSaleStrategy")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant ZoraTimedSaleStrategyStorageLocation = 0xe011f00dc6461ce60c6549a992e2b5cccb7ae98ed8fc0ee04eadce4204ebee00;

    /// @dev keccak256(abi.encode(uint256(keccak256("zora.storage.ZoraTimedSaleStrategyV2")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant ZoraTimedSaleStrategyStorageV2Location = 0xa7847b5c257e8ee3599bc3b02fee2b300998969f6fb6eaeafa73f9412bb1eb00;

    /// @dev keccak256(abi.encode(uint256(keccak256("zora.storage.ZoraTimedSaleStrategyRewardsVersion")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant ZoraTimedSaleStrategyRewardsVersionStorageLocation = 0xe2440be7925950e64511c898154abfbd7d8b923c6d4ff1e8f5f34478e5afda00;

    /// @notice Returns the storage struct for the Zora Timed Sale Strategy
    function _getZoraTimedSaleStrategyStorage() internal pure returns (IZoraTimedSaleStrategy.ZoraTimedSaleStrategyStorage storage strategyStorage) {
        assembly {
            strategyStorage.slot := ZoraTimedSaleStrategyStorageLocation
        }
    }

    /// @notice Returns the storage struct for the Zora Timed Sale Strategy
    function _getZoraTimedSaleStrategyStorageV2() internal pure returns (IZoraTimedSaleStrategy.ZoraTimedSaleStrategyStorageV2 storage strategyStorage) {
        assembly {
            strategyStorage.slot := ZoraTimedSaleStrategyStorageV2Location
        }
    }

    /// @notice Returns the rewards version storage struct for the Zora Timed Sale Strategy
    function _getZoraTimedSaleStrategyRewardsVersionStorage()
        internal
        pure
        returns (IZoraTimedSaleStrategy.ZoraTimedSaleStrategyRewardsVersionStorage storage rewardsVersionStorage)
    {
        assembly {
            rewardsVersionStorage.slot := ZoraTimedSaleStrategyRewardsVersionStorageLocation
        }
    }
}
