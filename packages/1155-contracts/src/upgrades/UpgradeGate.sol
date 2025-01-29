// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IUpgradeGate} from "../interfaces/IUpgradeGate.sol";
import {Ownable2StepUpgradeable} from "../utils/ownable/Ownable2StepUpgradeable.sol";
import {UpgradeGateStorageV1} from "./UpgradeGateStorageV1.sol";

/// @title UpgradeGate
/// @notice Contract for managing upgrades and safe upgrade paths for 1155 contracts
contract UpgradeGate is IUpgradeGate, Ownable2StepUpgradeable, UpgradeGateStorageV1 {
    /// @notice Constructor for deployment pathway. This contract needs to be atomically initialized to be safe.
    constructor() {}

    /// @notice Default owner initializer. Allows for shared deterministic addresses.
    /// @param _initialOwner initial owner for the contract
    function initialize(address _initialOwner) external initializer {
        __Ownable_init(_initialOwner);
        emit UpgradeGateSetup();
    }

    /// @notice The URI of the upgrade gate contract
    function contractURI() external pure returns (string memory) {
        return "https://github.com/ourzora/zora-1155-contracts/";
    }

    /// @notice The name of the upgrade gate contract
    function contractName() external pure returns (string memory) {
        return "ZORA 1155 Upgrade Gate";
    }

    ///                                                          ///
    ///                   CREATOR TOKEN UPGRADES                 ///
    ///                                                          ///

    /// @notice If an implementation is registered as an optional upgrade
    /// @param baseImpl The base implementation address
    /// @param upgradeImpl The upgrade implementation address
    function isRegisteredUpgradePath(address baseImpl, address upgradeImpl) public view returns (bool) {
        return isAllowedUpgrade[baseImpl][upgradeImpl];
    }

    /// @notice Registers optional upgrades
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

    /// @notice Removes an upgrade
    /// @param baseImpl The base implementation address
    /// @param upgradeImpl The upgrade implementation address
    function removeUpgradePath(address baseImpl, address upgradeImpl) public onlyOwner {
        delete isAllowedUpgrade[baseImpl][upgradeImpl];

        emit UpgradeRemoved(baseImpl, upgradeImpl);
    }
}
