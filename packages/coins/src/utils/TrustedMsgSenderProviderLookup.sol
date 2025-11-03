// SPDX-License-Identifier: ZORA-DELAYED-OSL-v1
// This software is licensed under the Zora Delayed Open Source License.
// Under this license, you may use, copy, modify, and distribute this software for
// non-commercial purposes only. Commercial use and competitive products are prohibited
// until the "Open Date" (3 years from first public distribution or earlier at Zora's discretion),
// at which point this software automatically becomes available under the MIT License.
// Full license terms available at: https://docs.zora.co/coins/license
pragma solidity ^0.8.23;

import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ContractVersionBase} from "../version/ContractVersionBase.sol";
import {ITrustedMsgSenderProviderLookup} from "../interfaces/ITrustedMsgSenderProviderLookup.sol";

/// @title TrustedMsgSenderProviderLookup
/// @notice Contract for ITrustedMsgSenderProviderLookup that manages trusted message senders
/// @dev This contract allows the owner to add/remove trusted senders and provides lookup functionality
contract TrustedMsgSenderProviderLookup is ITrustedMsgSenderProviderLookup, ContractVersionBase, Ownable2Step {
    /// @notice Emitted when a trusted sender is added
    /// @param sender The address that was added as trusted
    event TrustedSenderAdded(address indexed sender);

    /// @notice Emitted when a trusted sender is removed
    /// @param sender The address that was removed from trusted
    event TrustedSenderRemoved(address indexed sender);

    /// @notice Mapping of addresses to their trusted sender status
    mapping(address => bool) private trustedSenders;

    /// @notice Constructor that initializes the contract with trusted senders and sets the owner
    /// @param trustedMessageSenders Array of addresses to mark as trusted senders initially
    /// @param initialOwner The address that will own this contract
    constructor(address[] memory trustedMessageSenders, address initialOwner) Ownable(initialOwner) {
        for (uint256 i = 0; i < trustedMessageSenders.length; i++) {
            trustedSenders[trustedMessageSenders[i]] = true;
            emit TrustedSenderAdded(trustedMessageSenders[i]);
        }
    }

    /// @notice Checks if an address is a trusted message sender provider
    /// @param sender The address to check
    /// @return true if the sender is trusted, false otherwise
    function isTrustedMsgSenderProvider(address sender) external view override returns (bool) {
        return trustedSenders[sender];
    }

    /// @notice Adds multiple trusted senders in a single transaction (only callable by owner)
    /// @param senders Array of addresses to add as trusted
    function addTrustedMsgSenderProviders(address[] calldata senders) external onlyOwner {
        for (uint256 i = 0; i < senders.length; i++) {
            address sender = senders[i];
            require(sender != address(0), "Cannot add zero address as trusted sender");

            if (!trustedSenders[sender]) {
                trustedSenders[sender] = true;
                emit TrustedSenderAdded(sender);
            }
        }
    }

    /// @notice Removes multiple trusted senders in a single transaction (only callable by owner)
    /// @param senders Array of addresses to remove from trusted
    function removeTrustedMsgSenderProviders(address[] calldata senders) external onlyOwner {
        for (uint256 i = 0; i < senders.length; i++) {
            address sender = senders[i];

            if (trustedSenders[sender]) {
                trustedSenders[sender] = false;
                emit TrustedSenderRemoved(sender);
            }
        }
    }
}
