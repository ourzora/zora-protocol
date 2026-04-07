// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import {HooksDeployment} from "../src/libs/HooksDeployment.sol";
import {ContractAddresses} from "./utils/ContractAddresses.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookUpgradeGate} from "../src/hooks/HookUpgradeGate.sol";
import {ITrustedMsgSenderProviderLookup} from "../src/interfaces/ITrustedMsgSenderProviderLookup.sol";
import {TrustedSenderTestHelper} from "./utils/TrustedSenderTestHelper.sol";
import {ZoraHookRegistry} from "../src/hook-registry/ZoraHookRegistry.sol";

contract HooksDeploymentTest is Test, ContractAddresses {
    address internal hookUpgradeGate;
    ITrustedMsgSenderProviderLookup internal trustedMsgSenderLookup;
    address internal mockHookRegistry;
    address internal owner;
    address internal nonOwner;
    address internal trustedSender1;
    address internal trustedSender2;
    address internal nonTrustedSender;

    function setUp() public {
        vm.createSelectFork("base", 31653138);

        owner = makeAddr("owner");
        nonOwner = makeAddr("nonOwner");
        trustedSender1 = makeAddr("trustedSender1");
        trustedSender2 = makeAddr("trustedSender2");
        nonTrustedSender = makeAddr("nonTrustedSender");

        hookUpgradeGate = address(new HookUpgradeGate(makeAddr("factoryOwner")));
        mockHookRegistry = makeAddr("mockHookRegistry");

        // Initialize with one trusted sender
        address[] memory initialTrustedSenders = new address[](1);
        initialTrustedSenders[0] = trustedSender1;

        trustedMsgSenderLookup = TrustedSenderTestHelper.deployTrustedMessageSender(owner, initialTrustedSenders);
    }

    function test_canMineAndCacheSalt() public {
        address[] memory trustedMessageSenders = new address[](0);

        ITrustedMsgSenderProviderLookup localTrustedMsgSenderLookup = TrustedSenderTestHelper.deployTrustedMessageSender(
            makeAddr("owner"),
            trustedMessageSenders
        );

        (bytes32 salt, ) = HooksDeployment.mineAndCacheSalt(
            address(this),
            abi.encode(
                V4_POOL_MANAGER,
                0x777777751622c0d3258f214F9DF38E35BF45baF3,
                ITrustedMsgSenderProviderLookup(address(localTrustedMsgSenderLookup)),
                address(hookUpgradeGate)
            )
        );

        (bytes32 salt2, bool wasCached2) = HooksDeployment.mineAndCacheSalt(
            address(this),
            abi.encode(
                V4_POOL_MANAGER,
                0x777777751622c0d3258f214F9DF38E35BF45baF3,
                ITrustedMsgSenderProviderLookup(address(localTrustedMsgSenderLookup)),
                address(hookUpgradeGate)
            )
        );

        assertEq(salt, salt2);
        // make sure that on second, run, the salt is cached
        assertTrue(wasCached2);
    }

    function test_canDeployContentCoinHookFromScript() public {
        vm.createSelectFork("base", 31653138);

        address mockOrderFiller = makeAddr("mockOrderFiller");
        address[] memory trustedMessageSenders = new address[](0);

        ITrustedMsgSenderProviderLookup localTrustedMsgSenderLookup = TrustedSenderTestHelper.deployTrustedMessageSender(
            makeAddr("owner"),
            trustedMessageSenders
        );

        (, bytes32 salt) = HooksDeployment.mineForCoinSalt(
            address(this),
            V4_POOL_MANAGER,
            0x777777751622c0d3258f214F9DF38E35BF45baF3,
            ITrustedMsgSenderProviderLookup(address(localTrustedMsgSenderLookup)),
            hookUpgradeGate,
            mockOrderFiller,
            mockHookRegistry
        );
        IHooks hook = HooksDeployment.deployZoraV4CoinHook(
            V4_POOL_MANAGER,
            0x777777751622c0d3258f214F9DF38E35BF45baF3,
            ITrustedMsgSenderProviderLookup(address(localTrustedMsgSenderLookup)),
            hookUpgradeGate,
            mockOrderFiller,
            mockHookRegistry,
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

        address mockOrderFiller = makeAddr("mockOrderFiller");
        address[] memory trustedMessageSenders = new address[](0);

        ITrustedMsgSenderProviderLookup localTrustedMsgSenderLookup = TrustedSenderTestHelper.deployTrustedMessageSender(
            makeAddr("owner"),
            trustedMessageSenders
        );

        (, bytes32 salt) = HooksDeployment.mineForCoinSalt(
            address(this),
            V4_POOL_MANAGER,
            0x777777751622c0d3258f214F9DF38E35BF45baF3,
            ITrustedMsgSenderProviderLookup(address(localTrustedMsgSenderLookup)),
            hookUpgradeGate,
            mockOrderFiller,
            mockHookRegistry
        );

        IHooks hook = HooksDeployment.deployHookWithSalt(
            HooksDeployment.makeHookCreationCode(
                V4_POOL_MANAGER,
                0x777777751622c0d3258f214F9DF38E35BF45baF3,
                ITrustedMsgSenderProviderLookup(address(localTrustedMsgSenderLookup)),
                hookUpgradeGate,
                mockOrderFiller,
                mockHookRegistry
            ),
            salt
        );

        console.log("creator hook address", address(hook));
        console.log("creator coin salt:");
        console.logBytes32(salt);

        bool isValidHook = Hooks.isValidHookAddress(hook, 1000);

        assertTrue(isValidHook);
    }
}
