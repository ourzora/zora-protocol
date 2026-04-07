// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

import {IUpgradeGate} from "@zoralabs/shared-contracts/interfaces/IUpgradeGate.sol";
import {UpgradeGateStorageV1} from "./UpgradeGateStorageV1.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title UpgradeGate
/// @notice Contract for managing upgrades and safe upgrade paths for 1155 contracts
contract UpgradeGate is IUpgradeGate, Ownable2Step, UpgradeGateStorageV1 {
    string public contractName;
    string public contractURI;

    bool initialOwnershipTransferred;
    error InitialOwnershipAlreadyTransferred();

    /// @notice Constructor for deployment pathway. This contract needs to be atomically initialized to be safe.
    constructor(string memory _contractName, string memory _contractURI) Ownable(msg.sender) {
        contractName = _contractName;
        contractURI = _contractURI;
    }

    /// @notice Transfer initial ownership to the given address without needing to do the 2 step process
    /// Useful for when we want to separate constructor from initialization, to have the same deterministic address
    /// across chains.
    /// @param _initialOwner initial owner for the contract
    function transferInitialOwnership(address _initialOwner) external onlyOwner {
        if (initialOwnershipTransferred) {
            revert InitialOwnershipAlreadyTransferred();
        }
        initialOwnershipTransferred = true;
        _transferOwnership(_initialOwner);
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
