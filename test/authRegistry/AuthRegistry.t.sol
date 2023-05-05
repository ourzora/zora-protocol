// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import {AuthRegistry} from "../../src/authRegistry/AuthRegistry.sol";

contract AuthRegistryTest is Test {
    address owner;
    AuthRegistry authRegistry;

    event AuthorizedSet(address indexed account, bool authorized);

    function setUp() external {
        owner = vm.addr(1);

        vm.prank(owner);
        authRegistry = new AuthRegistry();
    }

    function test_owner_canAddAuthorized() external {
        address toAddA = vm.addr(2);
        address toAddB = vm.addr(3);

        assertFalse(authRegistry.isAuthorized(toAddA));
        assertFalse(authRegistry.isAuthorized(toAddB));

        vm.startPrank(owner);
        vm.expectEmit(true, false, false, true);
        emit AuthorizedSet(toAddA, true);
        authRegistry.setAuthorized(toAddA, true);
        authRegistry.setAuthorized(toAddB, true);

        vm.stopPrank();

        assertTrue(authRegistry.isAuthorized(toAddA));
        assertTrue(authRegistry.isAuthorized(toAddB));
    }

    function test_owner_canRemoveAuthorized() external {
        address toAddA = vm.addr(2);
        assertFalse(authRegistry.isAuthorized(toAddA));

        vm.startPrank(owner);

        authRegistry.setAuthorized(toAddA, true);
        assertTrue(authRegistry.isAuthorized(toAddA));

        vm.expectEmit(true, false, false, true);
        emit AuthorizedSet(toAddA, false);
        authRegistry.setAuthorized(toAddA, false);
        assertFalse(authRegistry.isAuthorized(toAddA));

        vm.stopPrank();
    }

    function test_nonOwner_cannotAddAuthorized() external {
        address anotherUser = vm.addr(2);

        vm.startPrank(anotherUser);
        vm.expectRevert("Ownable: caller is not the owner");
        authRegistry.setAuthorized(vm.addr(3), true);
        vm.expectRevert("Ownable: caller is not the owner");
        authRegistry.setAuthorized(vm.addr(3), false);
    }
}
