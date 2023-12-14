// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IZoraAccountUpgradeGate} from "../interfaces/IZoraAccountUpgradeGate.sol";
import {IZoraAccountOwnership} from "../interfaces/IZoraAccountOwnership.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";

contract ZoraAccountUpgradeGate is IZoraAccountUpgradeGate, IZoraAccountOwnership, Initializable, Ownable2StepUpgradeable {
    /// @notice Checks that an address is allowed to upgrade
    mapping(address => mapping(address => bool)) public isAllowedUpgrade;

    /// @notice Constructor for deployment pathway. This contract needs to be atomically initialized to be safe.
    constructor() {}

    /// @notice Default owner initializer. Allows for shared deterministic addresses.
    /// @param _initialOwner initial owner for the contract
    function initialize(address _initialOwner) external initializer {
        __Ownable_init(_initialOwner);
        emit UpgradeGateSetup();
    }

    /// @notice The name of the upgrade gate contract
    function contractName() external pure returns (string memory) {
        return "ZORA Account Abstraction Upgrade Gate";
    }

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
