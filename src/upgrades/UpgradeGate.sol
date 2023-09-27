// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IUpgradeGate} from "../interfaces/IUpgradeGate.sol";
import {Ownable2StepUpgradeable} from "../utils/ownable/Ownable2StepUpgradeable.sol";
import {UpgradeGateStorageV1} from "./UpgradeGateStorageV1.sol";

/// @title UpgradeGate
/// @notice Contract for managing upgrades and safe upgrade paths for 1155 contracts
contract UpgradeGate is IUpgradeGate, Ownable2StepUpgradeable, UpgradeGateStorageV1 {
    /// @notice Constructor for deployment pathway 
    constructor(address _defaultOwner) initializer {
        __Ownable_init(_defaultOwner);
        emit UpgradeGateSetup();
    }

    /// @notice ContractURI for contract information with the strategy
    function contractURI() external pure returns (string memory) {
        return "https://github.com/ourzora/zora-1155-contracts/";
    }

    /// @notice The name of the sale strategy
    function contractName() external pure returns (string memory) {
        return "ZORA 1155 Factory Managed Upgrade Gate";
    }

    ///                                                          ///
    ///                CREATOR TOKEN UPGRADES                    ///
    ///                                                          ///

    /// @notice If an implementation is registered by the Builder DAO as an optional upgrade
    /// @param baseImpl The base implementation address
    /// @param upgradeImpl The upgrade implementation address
    function isRegisteredUpgradePath(address baseImpl, address upgradeImpl) public view returns (bool) {
        return isAllowedUpgrade[baseImpl][upgradeImpl];
    }

    /// @notice Called by the Builder DAO to offer implementation upgrades for created DAOs
    /// @param baseImpls The base implementation addresses
    /// @param upgradeImpl The upgrade implementation address
    function registerUpgradePath(address[] memory baseImpls, address upgradeImpl) public onlyOwner {
        unchecked {
            for (uint256 i = 0; i < baseImpls.length; ++i) {
                isAllowedUpgrade[baseImpls[i]][upgradeImpl] = true;
                emit UpgradeRegistered(baseImpls[i], upgradeImpl);
            }
        }
    }

    /// @notice Called by the Builder DAO to remove an upgrade
    /// @param baseImpl The base implementation address
    /// @param upgradeImpl The upgrade implementation address
    function removeUpgradePath(address baseImpl, address upgradeImpl) public onlyOwner {
        delete isAllowedUpgrade[baseImpl][upgradeImpl];

        emit UpgradeRemoved(baseImpl, upgradeImpl);
    }
}
