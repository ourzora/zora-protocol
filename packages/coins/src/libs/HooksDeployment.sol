// SPDX-License-Identifier: ZORA-DELAYED-OSL-v1
// This software is licensed under the Zora Delayed Open Source License.
// Under this license, you may use, copy, modify, and distribute this software for
// non-commercial purposes only. Commercial use and competitive products are prohibited
// until the "Open Date" (3 years from first public distribution or earlier at Zora's discretion),
// at which point this software automatically becomes available under the MIT License.
// Full license terms available at: https://docs.zora.co/coins/license
pragma solidity ^0.8.23;

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {Vm} from "forge-std/Vm.sol";
import {ZoraV4CoinHook} from "../hooks/ZoraV4CoinHook.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";

Vm constant vm = Vm(address(bytes20(uint160(uint256(keccak256("hevm cheat code"))))));

// copy of hook miner from v4 periphery
// https://github.com/Uniswap/v4-periphery/blob/ad04c9f24a170accf5ea1b2836bbafd514537ca6/src/utils/HookMiner.sol#L23-L41
library HookMinerWithCreationCodeArgs {
    // mask to slice out the bottom 14 bit of the address
    uint160 constant FLAG_MASK = Hooks.ALL_HOOK_MASK; // 0000 ... 0000 0011 1111 1111 1111

    // Maximum number of iterations to find a salt, avoid infinite loops or MemoryOOG
    // (arbitrarily set)
    uint256 constant MAX_LOOP = 160_444;

    function deterministicHookAddress(address deployer, bytes32 salt, bytes memory creationCode) internal pure returns (address) {
        return Create2.computeAddress(salt, keccak256(creationCode), deployer);
    }

    /// @notice Find a salt that produces a hook address with the desired `flags`
    /// @param deployer The address that will deploy the hook. In `forge test`, this will be the test contract `address(this)` or the pranking address
    /// In `forge script`, this should be `0x4e59b44847b379578588920cA78FbF26c0B4956C` (CREATE2 Deployer Proxy)
    /// @param flags The desired flags for the hook address. Example `uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | ...)`
    /// @param creationCodeWithArgs The creation code of a hook contract, with encoded constructor arguments appended. Example: `abi.encodePacked(type(Counter).creationCode, abi.encode(constructorArg1, constructorArg2))`
    /// @return (hookAddress, salt) The hook deploys to `hookAddress` when using `salt` with the syntax: `new Hook{salt: salt}(<constructor arguments>)`
    function find(address deployer, uint160 flags, bytes memory creationCodeWithArgs) internal view returns (address, bytes32) {
        flags = flags & FLAG_MASK; // mask for only the bottom 14 bits

        address hookAddress;

        for (uint256 salt; salt < MAX_LOOP; salt++) {
            hookAddress = deterministicHookAddress(deployer, bytes32(salt), creationCodeWithArgs);

            // if the hook's bottom 14 bits match the desired flags AND the address does not have bytecode, we found a match
            if (uint160(hookAddress) & FLAG_MASK == flags && hookAddress.code.length == 0) {
                return (hookAddress, bytes32(salt));
            }
        }
        revert("HookMiner: could not find salt");
    }
}

library HooksDeployment {
    error HookNotDeployed();
    error InvalidHookAddress(address expected, address actual);

    bytes32 constant VALID_CONTENT_COIN_SALT = 0x0000000000000000000000000000000000000000000000000000000000002200;
    bytes32 constant VALID_CREATOR_COIN_SALT = 0x00000000000000000000000000000000000000000000000000000000000031af;

    function mineForSalt(address deployer, bytes memory hookCreationCode) internal view returns (address hookAddress, bytes32 salt) {
        uint160 flags = uint160(Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_INITIALIZE_FLAG) ^ (0x4444 << 144);
        return HookMinerWithCreationCodeArgs.find(deployer, flags, hookCreationCode);
    }

    function mineAndCacheSalt(address deployer, bytes memory hookCreationCode) internal returns (bytes32 salt, bool wasCached) {
        // look up in env the salt
        bytes32 envVarHash = keccak256(abi.encodePacked(deployer, hookCreationCode));
        string memory envKey = vm.toString(envVarHash);

        salt = vm.envOr(envKey, bytes32(0));

        if (salt == bytes32(0)) {
            (, salt) = mineForSalt(deployer, hookCreationCode);
            vm.setEnv(envKey, vm.toString(salt));
            wasCached = false;
        } else {
            wasCached = true;
        }
    }

    function mineForCoinSalt(
        address deployer,
        address poolManager,
        address coinVersionLookup,
        address[] memory trustedMessageSenders,
        address upgradeGate
    ) internal returns (address hookAddress, bytes32 salt) {
        bytes memory hookCreationCode = makeHookCreationCode(poolManager, coinVersionLookup, trustedMessageSenders, upgradeGate);
        (salt, ) = mineAndCacheSalt(deployer, hookCreationCode);
        hookAddress = HookMinerWithCreationCodeArgs.deterministicHookAddress(deployer, salt, hookCreationCode);
    }

    function deployHookWithSalt(bytes memory hookCreationCode, bytes32 salt) internal returns (IHooks hook) {
        address deployer = address(this);
        // Check if hook is already deployed
        (bool isDeployed, address existingHookAddress) = hooksIsDeployed(deployer, hookCreationCode, salt);
        if (isDeployed) {
            return IHooks(existingHookAddress);
        }

        // Deploy the hook with the provided salt
        hook = IHooks(Create2.deploy(0, salt, hookCreationCode));

        require(address(hook).code.length > 0, HookNotDeployed());

        address expectedAddress = HookMinerWithCreationCodeArgs.deterministicHookAddress(address(this), salt, hookCreationCode);
        require(expectedAddress == address(hook), InvalidHookAddress(expectedAddress, address(hook)));
    }

    /// @notice Checks if ContentCoinHook is already deployed for given parameters
    /// @param deployer The address that will deploy the hook
    /// @param hookCreationCode The creation code of the hook
    /// @param existingSalt The salt of the existing hook
    /// @return isDeployed True if hook is already deployed
    /// @return hookAddress The address where the hook would be/is deployed
    function hooksIsDeployed(
        address deployer,
        bytes memory hookCreationCode,
        bytes32 existingSalt
    ) internal view returns (bool isDeployed, address hookAddress) {
        hookAddress = HookMinerWithCreationCodeArgs.deterministicHookAddress(deployer, existingSalt, hookCreationCode);

        // Check if code exists at the predicted address
        isDeployed = hookAddress.code.length > 0;
    }

    function hookConstructorArgs(
        address poolManager,
        address coinVersionLookup,
        address[] memory trustedMessageSenders,
        address upgradeGate
    ) internal pure returns (bytes memory) {
        return abi.encode(poolManager, coinVersionLookup, trustedMessageSenders, upgradeGate);
    }

    function makeHookCreationCode(
        address poolManager,
        address coinVersionLookup,
        address[] memory trustedMessageSenders,
        address upgradeGate
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(type(ZoraV4CoinHook).creationCode, hookConstructorArgs(poolManager, coinVersionLookup, trustedMessageSenders, upgradeGate));
    }

    /// @notice Deploys or returns existing ContentCoinHook using deterministic deployment.  Ensures that if a hooks is already
    /// deployed with the provided salt, it will be returned.
    function deployZoraV4CoinHook(
        address poolManager,
        address coinVersionLookup,
        address[] memory trustedMessageSenders,
        address upgradeGate,
        bytes32 salt
    ) internal returns (IHooks hook) {
        bytes memory creationCode = makeHookCreationCode(poolManager, coinVersionLookup, trustedMessageSenders, upgradeGate);
        return deployHookWithSalt(creationCode, salt);
    }

    address constant FOUNDRY_SCRIPT_ADDRESS = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    function deployHookWithExistingOrNewSalt(
        address deployer,
        bytes memory _hookCreationCode,
        bytes32 salt
    ) internal returns (IHooks hook, bytes32 resultingSalt) {
        (bool isDeployed, address existingHookAddress) = hooksIsDeployed(deployer, _hookCreationCode, salt);

        if (isDeployed) {
            hook = IHooks(existingHookAddress);
            resultingSalt = salt;
        } else {
            (, resultingSalt) = mineForSalt(deployer, _hookCreationCode);
            hook = IHooks(Create2.deploy(0, resultingSalt, _hookCreationCode));
        }
    }
}
