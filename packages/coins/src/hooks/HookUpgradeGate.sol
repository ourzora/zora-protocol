// SPDX-License-Identifier: ZORA-DELAYED-OSL-v1
// This software is licensed under the Zora Delayed Open Source License.
// Under this license, you may use, copy, modify, and distribute this software for
// non-commercial purposes only. Commercial use and competitive products are prohibited
// until the "Open Date" (3 years from first public distribution or earlier at Zora's discretion),
// at which point this software automatically becomes available under the MIT License.
// Full license terms available at: https://docs.zora.co/coins/license
pragma solidity ^0.8.23;

import {IHooksUpgradeGate} from "../interfaces/IHooksUpgradeGate.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";

/// @title HookUpgradeGate
/// @notice Contract for managing upgrades and safe upgrade paths for V4 coin hooks
contract HookUpgradeGate is IHooksUpgradeGate, Ownable2Step {
    /// @notice Mapping of allowed upgrade paths: oldHook => newHook => allowed
    mapping(address => mapping(address => bool)) public isAllowedHookUpgrade;

    /// @notice Constructor for deployment pathway
    constructor(address owner) Ownable(owner) {}

    /// @notice If an implementation is registered as an optional upgrade
    /// @param baseImpl The base implementation address
    /// @param upgradeImpl The upgrade implementation address
    function isRegisteredUpgradePath(address baseImpl, address upgradeImpl) external view returns (bool) {
        return isAllowedHookUpgrade[baseImpl][upgradeImpl];
    }

    /// @notice Registers optional upgrades
    /// @param baseImpls The base implementation addresses
    /// @param upgradeImpl The upgrade implementation address
    function registerUpgradePath(address[] memory baseImpls, address upgradeImpl) external onlyOwner {
        for (uint256 i = 0; i < baseImpls.length; i++) {
            isAllowedHookUpgrade[baseImpls[i]][upgradeImpl] = true;
            emit UpgradeRegistered(baseImpls[i], upgradeImpl);
        }
    }

    /// @notice Removes an upgrade path
    /// @param baseImpl The base implementation address
    /// @param upgradeImpl The upgrade implementation address
    function removeUpgradePath(address baseImpl, address upgradeImpl) external onlyOwner {
        isAllowedHookUpgrade[baseImpl][upgradeImpl] = false;
        emit UpgradeRemoved(baseImpl, upgradeImpl);
    }
}
