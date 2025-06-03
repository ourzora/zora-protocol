// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {ZoraV4CoinHook} from "../hooks/ZoraV4CoinHook.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";

// copy of hook miner from v4 periphery
library HookMinerWithCreationCodeArgs {
    // mask to slice out the bottom 14 bit of the address
    uint160 constant FLAG_MASK = Hooks.ALL_HOOK_MASK; // 0000 ... 0000 0011 1111 1111 1111

    // Maximum number of iterations to find a salt, avoid infinite loops or MemoryOOG
    // (arbitrarily set)
    uint256 constant MAX_LOOP = 160_444;

    /// @notice Find a salt that produces a hook address with the desired `flags`
    /// @param deployer The address that will deploy the hook. In `forge test`, this will be the test contract `address(this)` or the pranking address
    /// In `forge script`, this should be `0x4e59b44847b379578588920cA78FbF26c0B4956C` (CREATE2 Deployer Proxy)
    /// @param flags The desired flags for the hook address. Example `uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | ...)`
    /// @param creationCodeWithArgs The creation code of a hook contract, with encoded constructor arguments appended. Example: `abi.encodePacked(type(Counter).creationCode, abi.encode(constructorArg1, constructorArg2))`
    /// @return (hookAddress, salt) The hook deploys to `hookAddress` when using `salt` with the syntax: `new Hook{salt: salt}(<constructor arguments>)`
    function find(address deployer, uint160 flags, bytes memory creationCodeWithArgs) internal view returns (address, bytes32) {
        flags = flags & FLAG_MASK; // mask for only the bottom 14 bits

        address hookAddress;

        bytes32 creationCodeHash = keccak256(creationCodeWithArgs);
        for (uint256 salt; salt < MAX_LOOP; salt++) {
            hookAddress = Create2.computeAddress(bytes32(salt), creationCodeHash, deployer);

            // if the hook's bottom 14 bits match the desired flags AND the address does not have bytecode, we found a match
            if (uint160(hookAddress) & FLAG_MASK == flags && hookAddress.code.length == 0) {
                return (hookAddress, bytes32(salt));
            }
        }
        revert("HookMiner: could not find salt");
    }
}

library HooksDeployment {
    function deployZoraV4CoinHook(address deployer, bytes memory hookCreationCode) internal returns (IHooks hook) {
        uint160 flags = uint160(Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_INITIALIZE_FLAG) ^ (0x4444 << 144);

        (address hookAddress, bytes32 salt) = HookMinerWithCreationCodeArgs.find(deployer, flags, hookCreationCode);

        hook = IHooks(Create2.deploy(0, salt, hookCreationCode));

        require(address(hook).code.length > 0, IHookDeployer.HookNotDeployed());

        require(hookAddress == address(hook), IHookDeployer.InvalidHookAddress(hookAddress, address(hook)));
    }

    function zoraV4CoinHookCreationCode(
        address poolManager,
        address coinVersionLookup,
        address[] memory trustedMessageSenders
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(type(ZoraV4CoinHook).creationCode, abi.encode(poolManager, coinVersionLookup, trustedMessageSenders));
    }

    function deployZoraV4CoinHookFromContract(
        address poolManager,
        address coinVersionLookup,
        address[] memory trustedMessageSenders
    ) internal returns (IHooks hook) {
        return deployZoraV4CoinHook(address(this), zoraV4CoinHookCreationCode(poolManager, coinVersionLookup, trustedMessageSenders));
    }

    function deployZoraV4CoinHookFromScript(
        address poolManager,
        address coinVersionLookup,
        address[] memory trustedMessageSenders
    ) internal returns (IHooks hook) {
        address deployer = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
        return deployZoraV4CoinHook(deployer, zoraV4CoinHookCreationCode(poolManager, coinVersionLookup, trustedMessageSenders));
    }
}

interface IHookDeployer {
    error HookNotDeployed();
    error InvalidHookAddress(address expected, address actual);
}
