// SPDX-License-Identifier: ZORA-DELAYED-OSL-v1
// This software is licensed under the Zora Delayed Open Source License.
// Under this license, you may use, copy, modify, and distribute this software for
// non-commercial purposes only. Commercial use and competitive products are prohibited
// until the "Open Date" (3 years from first public distribution or earlier at Zora's discretion),
// at which point this software automatically becomes available under the MIT License.
// Full license terms available at: https://docs.zora.co/coins/license
pragma solidity ^0.8.23;

interface IZoraHookRegistry {
    /// @notice Zora hook data
    struct ZoraHook {
        address hook;
        string tag;
        string version;
    }

    /// @notice Emitted when a hook is added to the registry
    event ZoraHookRegistered(address indexed hook, string tag, string version);

    /// @notice Emitted when a hook is removed from the registry
    event ZoraHookRemoved(address indexed hook, string tag, string version);

    /// @dev Reverts when the length of the hooks and tags arrays do not match
    error ArrayLengthMismatch();

    /// @notice Returns whether a hook is currently registered
    function isRegisteredHook(address hook) external view returns (bool);

    /// @notice Returns all registered hooks
    function getHooks() external view returns (ZoraHook[] memory);

    /// @notice Returns all registered hook addresses
    function getHookAddresses() external view returns (address[] memory);

    /// @notice Returns the tag for a hook
    function getHookTag(address hook) external view returns (string memory);

    /// @notice Returns the contract version for a hook if it exists
    function getHookVersion(address hook) external view returns (string memory);

    /// @notice Adds hooks to the registry
    function registerHooks(address[] calldata hooks, string[] calldata tags) external;

    /// @notice Removes hooks from the registry
    function removeHooks(address[] calldata hooks) external;
}
