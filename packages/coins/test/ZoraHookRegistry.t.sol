// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "forge-std/Test.sol";

import {IZoraHookRegistry} from "../src/interfaces/IZoraHookRegistry.sol";
import {ZoraHookRegistry} from "../src/hook-registry/ZoraHookRegistry.sol";

contract MockHook {
    function contractVersion() public pure returns (string memory) {
        return "0.0.0";
    }
}

contract ZoraHookRegistryTest is Test {
    uint256 internal forkId;
    address internal owner;

    ZoraHookRegistry internal zoraHookRegistry;
    MockHook internal mockHook;

    function setUp() public {
        forkId = vm.createSelectFork("base", 34509280);
        owner = makeAddr("owner");

        address[] memory initialOwners = new address[](1);
        initialOwners[0] = owner;

        zoraHookRegistry = new ZoraHookRegistry();
        zoraHookRegistry.initialize(initialOwners);

        mockHook = new MockHook();
    }

    function test_register_hooks() public {
        address[] memory hooks = new address[](1);
        string[] memory tags = new string[](1);

        hooks[0] = address(mockHook);
        tags[0] = "ZoraHook";

        vm.prank(owner);
        zoraHookRegistry.registerHooks(hooks, tags);

        assertEq(zoraHookRegistry.isRegisteredHook(hooks[0]), true);

        address[] memory addrs = zoraHookRegistry.getHookAddresses();
        assertEq(addrs.length, 1);
        assertEq(addrs[0], hooks[0]);

        assertEq(zoraHookRegistry.getHookTag(hooks[0]), tags[0]);

        IZoraHookRegistry.ZoraHook[] memory zoraHooks = zoraHookRegistry.getHooks();
        assertEq(zoraHooks.length, 1);
        assertEq(zoraHooks[0].hook, hooks[0]);
        assertEq(zoraHooks[0].tag, "ZoraHook");
        assertEq(zoraHooks[0].version, "0.0.0");
    }

    function test_revert_register_hooks_only_owner() public {
        address[] memory hooks = new address[](1);
        string[] memory tags = new string[](1);

        hooks[0] = address(mockHook);
        tags[0] = "ZoraHook";

        vm.expectRevert(abi.encodeWithSignature("OnlyOwner()"));
        vm.prank(makeAddr("notOwner"));
        zoraHookRegistry.registerHooks(hooks, tags);
    }

    function test_revert_register_hooks_array_length_mismatch() public {
        address[] memory hooks = new address[](2);
        string[] memory tags = new string[](1);

        hooks[0] = address(mockHook);
        hooks[1] = makeAddr("anotherHook");
        tags[0] = "Tag0";

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSignature("ArrayLengthMismatch()"));
        zoraHookRegistry.registerHooks(hooks, tags);
    }

    function test_register_duplicate_is_idempotent() public {
        address[] memory hooks = new address[](1);
        string[] memory tags = new string[](1);

        hooks[0] = address(mockHook);
        tags[0] = "ZoraHook";

        vm.startPrank(owner);
        zoraHookRegistry.registerHooks(hooks, tags);
        zoraHookRegistry.registerHooks(hooks, tags);
        vm.stopPrank();

        assertEq(zoraHookRegistry.getHookAddresses().length, 1);
        assertEq(zoraHookRegistry.isRegisteredHook(hooks[0]), true);
    }

    function test_remove_hooks() public {
        address[] memory hooks = new address[](1);
        string[] memory tags = new string[](1);

        hooks[0] = address(mockHook);
        tags[0] = "ZoraHook";

        vm.prank(owner);
        zoraHookRegistry.registerHooks(hooks, tags);

        vm.prank(owner);
        zoraHookRegistry.removeHooks(hooks);

        assertEq(zoraHookRegistry.isRegisteredHook(hooks[0]), false);
        assertEq(zoraHookRegistry.getHookAddresses().length, 0);
        assertEq(zoraHookRegistry.getHookTag(hooks[0]), "");
    }

    function test_revert_remove_hooks_only_owner() public {
        address[] memory hooks = new address[](1);
        string[] memory tags = new string[](1);

        hooks[0] = address(mockHook);
        tags[0] = "ZoraHook";

        vm.prank(owner);
        zoraHookRegistry.registerHooks(hooks, tags);

        vm.expectRevert(abi.encodeWithSignature("OnlyOwner()"));
        vm.prank(makeAddr("notOwner"));
        zoraHookRegistry.removeHooks(hooks);
    }

    function test_remove_unregistered_noop() public {
        address[] memory hooks = new address[](1);
        hooks[0] = makeAddr("unregistered");

        uint256 beforeLen = zoraHookRegistry.getHookAddresses().length;

        vm.prank(owner);
        zoraHookRegistry.removeHooks(hooks);

        assertEq(zoraHookRegistry.getHookAddresses().length, beforeLen);
        assertEq(zoraHookRegistry.isRegisteredHook(hooks[0]), false);
    }

    function test_emit_register_hooks_event() public {
        address[] memory hooks = new address[](1);
        string[] memory tags = new string[](1);

        hooks[0] = address(mockHook);
        tags[0] = "ZoraHook";

        vm.expectEmit(true, true, true, false, address(zoraHookRegistry));
        emit IZoraHookRegistry.ZoraHookRegistered(hooks[0], tags[0], "0.0.0");

        vm.prank(owner);
        zoraHookRegistry.registerHooks(hooks, tags);
    }

    function test_emit_remove_hooks_event() public {
        address[] memory hooks = new address[](1);
        string[] memory tags = new string[](1);

        hooks[0] = address(mockHook);
        tags[0] = "ZoraHook";

        vm.prank(owner);
        zoraHookRegistry.registerHooks(hooks, tags);

        vm.expectEmit(true, true, true, false, address(zoraHookRegistry));
        emit IZoraHookRegistry.ZoraHookRemoved(hooks[0], tags[0], "0.0.0");

        vm.prank(owner);
        zoraHookRegistry.removeHooks(hooks);
    }

    function test_hook_version() public {
        address[] memory hooks = new address[](1);
        string[] memory tags = new string[](1);

        hooks[0] = 0x81542dC43Aff247eff4a0eceFC286A2973aE1040;
        tags[0] = "CONTENT";

        vm.prank(owner);
        zoraHookRegistry.registerHooks(hooks, tags);

        assertEq(zoraHookRegistry.getHookVersion(hooks[0]), "1.1.1");
    }

    function test_hook_version_not_found() public {
        address[] memory hooks = new address[](1);
        string[] memory tags = new string[](1);

        hooks[0] = 0xA1eBdD5cA6470Bbd67114331387f2dDa7bfad040;
        tags[0] = "CONTENT";

        vm.prank(owner);
        zoraHookRegistry.registerHooks(hooks, tags);

        assertEq(zoraHookRegistry.getHookVersion(hooks[0]), "");
    }

    function test_is_registered_hook_false_when_never_registered() public view {
        assertEq(zoraHookRegistry.isRegisteredHook(address(this)), false);
    }

    function test_get_hook_addresses_multiple_and_remove_middle() public {
        address a = address(mockHook);
        address b = address(new MockHook());
        address c = address(new MockHook());

        address[] memory hooks = new address[](3);
        string[] memory tags = new string[](3);
        hooks[0] = a;
        tags[0] = "A";
        hooks[1] = b;
        tags[1] = "B";
        hooks[2] = c;
        tags[2] = "C";

        vm.prank(owner);
        zoraHookRegistry.registerHooks(hooks, tags);

        address[] memory removeB = new address[](1);
        removeB[0] = b;

        vm.prank(owner);
        zoraHookRegistry.removeHooks(removeB);

        address[] memory addrs = zoraHookRegistry.getHookAddresses();
        assertEq(addrs.length, 2);

        bool hasA;
        bool hasC;
        for (uint256 i = 0; i < addrs.length; i++) {
            if (addrs[i] == a) hasA = true;
            if (addrs[i] == c) hasC = true;
            assertTrue(addrs[i] != b);
        }
        assertTrue(hasA);
        assertTrue(hasC);

        assertEq(zoraHookRegistry.getHookTag(a), "A");
        assertEq(zoraHookRegistry.getHookTag(b), "");
        assertEq(zoraHookRegistry.getHookTag(c), "C");

        IZoraHookRegistry.ZoraHook[] memory full = zoraHookRegistry.getHooks();
        assertEq(full.length, 2);

        bool okA;
        bool okC;
        for (uint256 i = 0; i < full.length; i++) {
            if (full[i].hook == a) {
                assertEq(full[i].tag, "A");
                assertEq(full[i].version, "0.0.0");
                okA = true;
            } else if (full[i].hook == c) {
                assertEq(full[i].tag, "C");
                assertEq(full[i].version, "0.0.0");
                okC = true;
            }
        }
        assertTrue(okA && okC);
    }
}
