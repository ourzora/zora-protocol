// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import {HooksDeployment} from "../src/libs/HooksDeployment.sol";
import {ContractAddresses} from "./utils/ContractAddresses.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookUpgradeGate} from "../src/hooks/HookUpgradeGate.sol";

contract HooksDeploymentTest is Test, ContractAddresses {
    address internal hookUpgradeGate;

    function setUp() public {
        vm.createSelectFork("base", 31653138);

        hookUpgradeGate = address(new HookUpgradeGate(makeAddr("factoryOwner")));
    }

    function test_canMineAndCacheSalt() public {
        address[] memory trustedMessageSenders = new address[](0);

        (bytes32 salt, ) = HooksDeployment.mineAndCacheSalt(
            address(this),
            abi.encode(V4_POOL_MANAGER, 0x777777751622c0d3258f214F9DF38E35BF45baF3, trustedMessageSenders, address(hookUpgradeGate))
        );

        (bytes32 salt2, bool wasCached2) = HooksDeployment.mineAndCacheSalt(
            address(this),
            abi.encode(V4_POOL_MANAGER, 0x777777751622c0d3258f214F9DF38E35BF45baF3, trustedMessageSenders, address(hookUpgradeGate))
        );

        assertEq(salt, salt2);
        // make sure that on second, run, the salt is cached
        assertTrue(wasCached2);
    }

    function test_canDeployContentCoinHookFromScript() public {
        vm.createSelectFork("base", 31653138);

        address[] memory trustedMessageSenders = new address[](0);
        (, bytes32 salt) = HooksDeployment.mineForCoinSalt(
            address(this),
            V4_POOL_MANAGER,
            0x777777751622c0d3258f214F9DF38E35BF45baF3,
            trustedMessageSenders,
            hookUpgradeGate
        );
        IHooks hook = HooksDeployment.deployZoraV4CoinHook(
            V4_POOL_MANAGER,
            0x777777751622c0d3258f214F9DF38E35BF45baF3,
            trustedMessageSenders,
            hookUpgradeGate,
            salt
        );

        bool isValidHook = Hooks.isValidHookAddress(hook, 1000);

        console.log("content hook address:", address(hook));
        console.log("content coin salt:");
        console.logBytes32(salt);

        assertTrue(isValidHook);
    }

    function test_canDeployCreatorCoinHookFromScript() public {
        vm.createSelectFork("base", 31653138);

        address[] memory trustedMessageSenders = new address[](0);
        (, bytes32 salt) = HooksDeployment.mineForCoinSalt(
            address(this),
            V4_POOL_MANAGER,
            0x777777751622c0d3258f214F9DF38E35BF45baF3,
            trustedMessageSenders,
            hookUpgradeGate
        );

        IHooks hook = HooksDeployment.deployHookWithSalt(
            HooksDeployment.makeHookCreationCode(V4_POOL_MANAGER, 0x777777751622c0d3258f214F9DF38E35BF45baF3, trustedMessageSenders, hookUpgradeGate),
            salt
        );

        console.log("creator hook address", address(hook));
        console.log("creator coin salt:");
        console.logBytes32(salt);

        bool isValidHook = Hooks.isValidHookAddress(hook, 1000);

        assertTrue(isValidHook);
    }
}
