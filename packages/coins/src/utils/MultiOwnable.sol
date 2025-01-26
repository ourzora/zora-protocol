// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/// @title MultiOwnable
/// @notice Allows multiple addresses to have owner privileges
contract MultiOwnable is Initializable {
    using EnumerableSet for EnumerableSet.AddressSet;

    event OwnerUpdated(address indexed caller, address indexed prevOwner, address indexed newOwner);

    error AlreadyOwner();
    error NotOwner();
    error OneOwnerRequired();
    error OwnerCannotBeAddressZero();
    error OnlyOwner();
    error UseRevokeOwnershipToRemoveSelf();

    EnumerableSet.AddressSet internal _owners;

    /// @notice Restricts function access to current owners
    modifier onlyOwner() {
        if (!isOwner(msg.sender)) {
            revert OnlyOwner();
        }
        _;
    }

    /// @dev Initializes the contract with a set of owners
    /// @param initialOwners An list of initial owner addresses
    function __MultiOwnable_init(address[] memory initialOwners) internal onlyInitializing {
        uint256 numOwners = initialOwners.length;

        if (numOwners == 0) {
            revert OneOwnerRequired();
        }

        for (uint256 i; i < numOwners; ++i) {
            if (initialOwners[i] == address(0)) {
                revert OwnerCannotBeAddressZero();
            }

            if (isOwner(initialOwners[i])) {
                revert AlreadyOwner();
            }

            _owners.add(initialOwners[i]);

            emit OwnerUpdated(msg.sender, address(0), initialOwners[i]);
        }
    }

    /// @notice Checks if an address is an owner
    /// @param account The address to check
    function isOwner(address account) public view returns (bool) {
        return _owners.contains(account);
    }

    /// @notice The current owner addresses
    function owners() public view returns (address[] memory) {
        return _owners.values();
    }

    /// @notice Adds multiple owners
    /// @param accounts The addresses to add as owners
    function addOwners(address[] memory accounts) public onlyOwner {
        for (uint256 i; i < accounts.length; ++i) {
            addOwner(accounts[i]);
        }
    }

    /// @notice Adds a new owner
    /// @dev Only callable by existing owners
    /// @param account The address to add as an owner
    function addOwner(address account) public onlyOwner {
        if (account == address(0)) {
            revert OwnerCannotBeAddressZero();
        }

        if (isOwner(account)) {
            revert AlreadyOwner();
        }

        _owners.add(account);

        emit OwnerUpdated(msg.sender, address(0), account);
    }

    /// @notice Removes multiple owners
    /// @param accounts The addresses to remove as owners
    function removeOwners(address[] memory accounts) public onlyOwner {
        for (uint256 i; i < accounts.length; ++i) {
            removeOwner(accounts[i]);
        }
    }

    /// @notice Removes an existing owner
    /// @dev Only callable by existing owners
    /// @param account The address to remove as an owner
    function removeOwner(address account) public onlyOwner {
        if (account == address(0)) {
            revert OwnerCannotBeAddressZero();
        }

        if (account == msg.sender) {
            revert UseRevokeOwnershipToRemoveSelf();
        }

        if (!isOwner(account)) {
            revert NotOwner();
        }

        _owners.remove(account);

        emit OwnerUpdated(msg.sender, account, address(0));
    }

    /// @notice Revokes ownership for the caller
    function revokeOwnership() public onlyOwner {
        _owners.remove(msg.sender);

        emit OwnerUpdated(msg.sender, msg.sender, address(0));
    }
}
