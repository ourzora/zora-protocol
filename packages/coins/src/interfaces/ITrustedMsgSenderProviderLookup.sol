// SPDX-License-Identifier: ZORA-DELAYED-OSL-v1
// This software is licensed under the Zora Delayed Open Source License.
// Under this license, you may use, copy, modify, and distribute this software for
// non-commercial purposes only. Commercial use and competitive products are prohibited
// until the "Open Date" (3 years from first public distribution or earlier at Zora's discretion),
// at which point this software automatically becomes available under the MIT License.
// Full license terms available at: https://docs.zora.co/coins/license
pragma solidity ^0.8.23;

/// @title ITrustedMsgSenderProviderLookup
/// @notice Interface for contracts that can determine if an address is a trusted message sender
/// @dev This interface allows the hook to delegate the trusted sender check to an external contract
interface ITrustedMsgSenderProviderLookup {
    /// @notice Checks if an address is a trusted message sender provider
    /// @param sender The address to check
    /// @return true if the sender is trusted, false otherwise
    function isTrustedMsgSenderProvider(address sender) external view returns (bool);
}
