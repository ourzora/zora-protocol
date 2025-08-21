// SPDX-License-Identifier: ZORA-DELAYED-OSL-v1
// This software is licensed under the Zora Delayed Open Source License.
// Under this license, you may use, copy, modify, and distribute this software for
// non-commercial purposes only. Commercial use and competitive products are prohibited
// until the "Open Date" (3 years from first public distribution or earlier at Zora's discretion),
// at which point this software automatically becomes available under the MIT License.
// Full license terms available at: https://docs.zora.co/coins/license
pragma solidity ^0.8.23;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IVersionedContract} from "@zoralabs/shared-contracts/interfaces/IVersionedContract.sol";
import {MultiOwnable} from "../utils/MultiOwnable.sol";
import {IZoraHookRegistry} from "../interfaces/IZoraHookRegistry.sol";

/// @title Zora Hook Registry
/// @notice A registry of Zora hook contracts for Uniswap V4
contract ZoraHookRegistry is IZoraHookRegistry, MultiOwnable {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @dev The set of registered hook addresses
    EnumerableSet.AddressSet internal registeredHooks;

    /// @dev The tag for each hook
    mapping(address hook => string tag) internal hookTags;

    constructor() {}

    /// @notice Initializes the registry with initial owners
    function initialize(address[] memory initialOwners) external initializer {
        __MultiOwnable_init(initialOwners);
    }

    /// @notice Returns whether a hook is currently registered
    function isRegisteredHook(address hook) external view returns (bool) {
        return registeredHooks.contains(hook);
    }

    /// @notice Returns all registered hooks
    function getHooks() external view returns (ZoraHook[] memory) {
        uint256 numHooks = registeredHooks.length();

        ZoraHook[] memory hooks = new ZoraHook[](numHooks);

        for (uint256 i; i < numHooks; i++) {
            address hook = registeredHooks.at(i);

            hooks[i] = ZoraHook({hook: hook, tag: getHookTag(hook), version: getHookVersion(hook)});
        }

        return hooks;
    }

    /// @notice Returns all registered hook addresses
    function getHookAddresses() external view returns (address[] memory) {
        return registeredHooks.values();
    }

    /// @notice Returns the tag for a hook
    function getHookTag(address hook) public view returns (string memory) {
        return hookTags[hook];
    }

    /// @notice Returns the contract version for a hook if it exists
    function getHookVersion(address hook) public pure returns (string memory version) {
        try IVersionedContract(hook).contractVersion() returns (string memory _version) {
            version = _version;
        } catch {}
    }

    /// @notice Adds hooks to the registry
    function registerHooks(address[] calldata hooks, string[] calldata tags) external onlyOwner {
        require(hooks.length == tags.length, ArrayLengthMismatch());

        for (uint256 i; i < hooks.length; i++) {
            if (registeredHooks.add(hooks[i])) {
                hookTags[hooks[i]] = tags[i];

                emit ZoraHookRegistered(hooks[i], tags[i], getHookVersion(hooks[i]));
            }
        }
    }

    /// @notice Removes hooks from the registry
    function removeHooks(address[] calldata hooks) external onlyOwner {
        for (uint256 i; i < hooks.length; i++) {
            if (registeredHooks.remove(hooks[i])) {
                emit ZoraHookRemoved(hooks[i], hookTags[hooks[i]], getHookVersion(hooks[i]));

                delete hookTags[hooks[i]];
            }
        }
    }
}
