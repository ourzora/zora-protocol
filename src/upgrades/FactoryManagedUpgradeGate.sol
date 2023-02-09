// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IFactoryManagedUpgradeGate} from "../interfaces/IFactoryManagedUpgradeGate.sol";
import {Ownable2StepUpgradeable} from "../utils/ownable/Ownable2StepUpgradeable.sol";
import {FactoryManagedUpgradeGateStorageV1} from "./FactoryManagedUpgradeGateStorageV1.sol";

abstract contract FactoryManagedUpgradeGate is
    IFactoryManagedUpgradeGate,
    Ownable2StepUpgradeable,
    FactoryManagedUpgradeGateStorageV1
{
    ///                                                          ///
    ///                CREATOR TOKEN UPGRADES                    ///
    ///                                                          ///

    /// @notice If an implementation is registered by the Builder DAO as an optional upgrade
    /// @param baseImpl The base implementation address
    /// @param upgradeImpl The upgrade implementation address
    function isRegisteredUpgradePath(address baseImpl, address upgradeImpl)
        public
        view
        returns (bool)
    {
        return isAllowedUpgrade[baseImpl][upgradeImpl];
    }

    /// @notice Called by the Builder DAO to offer implementation upgrades for created DAOs
    /// @param baseImpls The base implementation addresses
    /// @param upgradeImpl The upgrade implementation address
    function registerUpgradePath(
        address[] memory baseImpls,
        address upgradeImpl
    ) public onlyOwner {
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
    function removeUpgradePath(address baseImpl, address upgradeImpl)
        public
        onlyOwner
    {
        delete isAllowedUpgrade[baseImpl][upgradeImpl];

        emit UpgradeRemoved(baseImpl, upgradeImpl);
    }
}
