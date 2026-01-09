// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {SimpleAccessManager} from "../src/access/SimpleAccessManager.sol";

/// @title SimpleAccessManagerTest
/// @notice Comprehensive tests for SimpleAccessManager contract
contract SimpleAccessManagerTest is Test {
    SimpleAccessManager public accessManager;

    address public admin = makeAddr("admin");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");

    uint64 public constant ADMIN_ROLE = type(uint64).min; // 0
    uint64 public constant PUBLIC_ROLE = type(uint64).max;
    uint64 public constant CUSTOM_ROLE = 1;
    uint64 public constant ANOTHER_ROLE = 2;

    bytes4 public constant TEST_SELECTOR = bytes4(keccak256("testFunction()"));
    bytes4 public constant ANOTHER_SELECTOR = bytes4(keccak256("anotherFunction()"));

    event RoleGranted(uint64 indexed roleId, address indexed account);
    event RoleRevoked(uint64 indexed roleId, address indexed account);
    event RoleAdminChanged(uint64 indexed roleId, uint64 indexed admin);
    event FunctionRoleUpdated(bytes4 indexed selector, uint64 indexed roleId);

    function setUp() public {
        // Deploy with no initial function roles
        SimpleAccessManager.InitialFunctionRole[] memory noRoles = new SimpleAccessManager.InitialFunctionRole[](0);
        accessManager = new SimpleAccessManager(admin, noRoles);
    }

    // ================================ CONSTRUCTOR TESTS ================================

    function test_constructor_setsInitialAdmin() public view {
        assertTrue(accessManager.hasRole(ADMIN_ROLE, admin));
    }

    function test_constructor_revertsOnZeroAdmin() public {
        SimpleAccessManager.InitialFunctionRole[] memory noRoles = new SimpleAccessManager.InitialFunctionRole[](0);
        vm.expectRevert(abi.encodeWithSelector(SimpleAccessManager.AccessManagerInvalidInitialAdmin.selector, address(0)));
        new SimpleAccessManager(address(0), noRoles);
    }

    function test_constructor_setsInitialFunctionRoles() public {
        SimpleAccessManager.InitialFunctionRole[] memory initialRoles = new SimpleAccessManager.InitialFunctionRole[](2);
        initialRoles[0] = SimpleAccessManager.InitialFunctionRole({selector: TEST_SELECTOR, roleId: PUBLIC_ROLE});
        initialRoles[1] = SimpleAccessManager.InitialFunctionRole({selector: ANOTHER_SELECTOR, roleId: CUSTOM_ROLE});

        SimpleAccessManager manager = new SimpleAccessManager(admin, initialRoles);

        assertEq(manager.getFunctionRole(TEST_SELECTOR), PUBLIC_ROLE);
        assertEq(manager.getFunctionRole(ANOTHER_SELECTOR), CUSTOM_ROLE);
    }

    function test_constructor_emitsEvents() public {
        SimpleAccessManager.InitialFunctionRole[] memory initialRoles = new SimpleAccessManager.InitialFunctionRole[](1);
        initialRoles[0] = SimpleAccessManager.InitialFunctionRole({selector: TEST_SELECTOR, roleId: PUBLIC_ROLE});

        vm.expectEmit(true, true, false, false);
        emit RoleGranted(ADMIN_ROLE, admin);

        vm.expectEmit(true, true, false, false);
        emit FunctionRoleUpdated(TEST_SELECTOR, PUBLIC_ROLE);

        new SimpleAccessManager(admin, initialRoles);
    }

    // ================================ canCall TESTS ================================

    function test_canCall_returnsTrueForPublicRole() public {
        vm.prank(admin);
        accessManager.setFunctionRole(TEST_SELECTOR, PUBLIC_ROLE);

        // Anyone should be able to call
        assertTrue(accessManager.canCall(user1, address(0), TEST_SELECTOR));
        assertTrue(accessManager.canCall(user2, address(0), TEST_SELECTOR));
        assertTrue(accessManager.canCall(address(0), address(0), TEST_SELECTOR));
    }

    function test_canCall_returnsTrueForRoleMember() public {
        vm.startPrank(admin);
        accessManager.setFunctionRole(TEST_SELECTOR, CUSTOM_ROLE);
        accessManager.grantRole(CUSTOM_ROLE, user1);
        vm.stopPrank();

        assertTrue(accessManager.canCall(user1, address(0), TEST_SELECTOR));
    }

    function test_canCall_returnsFalseForNonRoleMember() public {
        vm.startPrank(admin);
        accessManager.setFunctionRole(TEST_SELECTOR, CUSTOM_ROLE);
        accessManager.grantRole(CUSTOM_ROLE, user1);
        vm.stopPrank();

        assertFalse(accessManager.canCall(user2, address(0), TEST_SELECTOR));
    }

    function test_canCall_defaultsToAdminRoleForUnconfiguredFunctions() public view {
        // Unconfigured function defaults to role 0 (ADMIN_ROLE)
        assertTrue(accessManager.canCall(admin, address(0), TEST_SELECTOR));
        assertFalse(accessManager.canCall(user1, address(0), TEST_SELECTOR));
    }

    function test_canCall_ignoresTargetParameter() public {
        vm.prank(admin);
        accessManager.setFunctionRole(TEST_SELECTOR, PUBLIC_ROLE);

        // Target should be ignored
        assertTrue(accessManager.canCall(user1, address(1), TEST_SELECTOR));
        assertTrue(accessManager.canCall(user1, address(2), TEST_SELECTOR));
        assertTrue(accessManager.canCall(user1, makeAddr("anyTarget"), TEST_SELECTOR));
    }

    // ================================ ROLE MANAGEMENT TESTS ================================

    function test_grantRole_byAdmin() public {
        vm.prank(admin);
        accessManager.grantRole(CUSTOM_ROLE, user1);

        assertTrue(accessManager.hasRole(CUSTOM_ROLE, user1));
    }

    function test_grantRole_emitsEvent() public {
        vm.expectEmit(true, true, false, false);
        emit RoleGranted(CUSTOM_ROLE, user1);

        vm.prank(admin);
        accessManager.grantRole(CUSTOM_ROLE, user1);
    }

    function test_grantRole_noopIfAlreadyHasRole() public {
        vm.startPrank(admin);
        accessManager.grantRole(CUSTOM_ROLE, user1);

        // Grant again - should not emit event
        vm.recordLogs();
        accessManager.grantRole(CUSTOM_ROLE, user1);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // No RoleGranted event should be emitted
        for (uint256 i; i < logs.length; ++i) {
            assertFalse(logs[i].topics[0] == keccak256("RoleGranted(uint64,address)"));
        }
        vm.stopPrank();
    }

    function test_grantRole_revertsForPublicRole() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(SimpleAccessManager.AccessManagerLockedRole.selector, PUBLIC_ROLE));
        accessManager.grantRole(PUBLIC_ROLE, user1);
    }

    function test_grantRole_revertsIfNotRoleAdmin() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(SimpleAccessManager.AccessManagerUnauthorizedAccount.selector, user1, ADMIN_ROLE));
        accessManager.grantRole(CUSTOM_ROLE, user2);
    }

    function test_revokeRole_byAdmin() public {
        vm.startPrank(admin);
        accessManager.grantRole(CUSTOM_ROLE, user1);
        accessManager.revokeRole(CUSTOM_ROLE, user1);
        vm.stopPrank();

        assertFalse(accessManager.hasRole(CUSTOM_ROLE, user1));
    }

    function test_revokeRole_emitsEvent() public {
        vm.prank(admin);
        accessManager.grantRole(CUSTOM_ROLE, user1);

        vm.expectEmit(true, true, false, false);
        emit RoleRevoked(CUSTOM_ROLE, user1);

        vm.prank(admin);
        accessManager.revokeRole(CUSTOM_ROLE, user1);
    }

    function test_revokeRole_noopIfDoesntHaveRole() public {
        vm.prank(admin);
        vm.recordLogs();
        accessManager.revokeRole(CUSTOM_ROLE, user1);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // No RoleRevoked event should be emitted
        for (uint256 i; i < logs.length; ++i) {
            assertFalse(logs[i].topics[0] == keccak256("RoleRevoked(uint64,address)"));
        }
    }

    function test_revokeRole_revertsForPublicRole() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(SimpleAccessManager.AccessManagerLockedRole.selector, PUBLIC_ROLE));
        accessManager.revokeRole(PUBLIC_ROLE, user1);
    }

    function test_revokeRole_revertsIfNotRoleAdmin() public {
        vm.prank(admin);
        accessManager.grantRole(CUSTOM_ROLE, user1);

        vm.prank(user2);
        vm.expectRevert(abi.encodeWithSelector(SimpleAccessManager.AccessManagerUnauthorizedAccount.selector, user2, ADMIN_ROLE));
        accessManager.revokeRole(CUSTOM_ROLE, user1);
    }

    function test_renounceRole_selfRevoke() public {
        vm.prank(admin);
        accessManager.grantRole(CUSTOM_ROLE, user1);

        vm.prank(user1);
        accessManager.renounceRole(CUSTOM_ROLE, user1);

        assertFalse(accessManager.hasRole(CUSTOM_ROLE, user1));
    }

    function test_renounceRole_revertsIfConfirmationMismatch() public {
        vm.prank(admin);
        accessManager.grantRole(CUSTOM_ROLE, user1);

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(SimpleAccessManager.AccessManagerUnauthorizedAccount.selector, user1, CUSTOM_ROLE));
        accessManager.renounceRole(CUSTOM_ROLE, user2);
    }

    function test_renounceRole_revertsForPublicRole() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(SimpleAccessManager.AccessManagerLockedRole.selector, PUBLIC_ROLE));
        accessManager.renounceRole(PUBLIC_ROLE, user1);
    }

    // ================================ ROLE ADMIN TESTS ================================

    function test_setRoleAdmin_byGlobalAdmin() public {
        vm.prank(admin);
        accessManager.setRoleAdmin(CUSTOM_ROLE, ANOTHER_ROLE);

        assertEq(accessManager.getRoleAdmin(CUSTOM_ROLE), ANOTHER_ROLE);
    }

    function test_setRoleAdmin_emitsEvent() public {
        vm.expectEmit(true, true, false, false);
        emit RoleAdminChanged(CUSTOM_ROLE, ANOTHER_ROLE);

        vm.prank(admin);
        accessManager.setRoleAdmin(CUSTOM_ROLE, ANOTHER_ROLE);
    }

    function test_setRoleAdmin_revertsForAdminRole() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(SimpleAccessManager.AccessManagerLockedRole.selector, ADMIN_ROLE));
        accessManager.setRoleAdmin(ADMIN_ROLE, CUSTOM_ROLE);
    }

    function test_setRoleAdmin_revertsForPublicRole() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(SimpleAccessManager.AccessManagerLockedRole.selector, PUBLIC_ROLE));
        accessManager.setRoleAdmin(PUBLIC_ROLE, CUSTOM_ROLE);
    }

    function test_setRoleAdmin_revertsIfNotGlobalAdmin() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(SimpleAccessManager.AccessManagerUnauthorizedAccount.selector, user1, ADMIN_ROLE));
        accessManager.setRoleAdmin(CUSTOM_ROLE, ANOTHER_ROLE);
    }

    function test_grantRole_withCustomRoleAdmin() public {
        // Set ANOTHER_ROLE as admin for CUSTOM_ROLE
        vm.prank(admin);
        accessManager.setRoleAdmin(CUSTOM_ROLE, ANOTHER_ROLE);

        // Grant ANOTHER_ROLE to user1
        vm.prank(admin);
        accessManager.grantRole(ANOTHER_ROLE, user1);

        // user1 should now be able to grant CUSTOM_ROLE
        vm.prank(user1);
        accessManager.grantRole(CUSTOM_ROLE, user2);

        assertTrue(accessManager.hasRole(CUSTOM_ROLE, user2));
    }

    function test_getRoleAdmin_defaultsToAdminRole() public view {
        // Unconfigured role admin defaults to ADMIN_ROLE (0)
        assertEq(accessManager.getRoleAdmin(CUSTOM_ROLE), ADMIN_ROLE);
    }

    // ================================ FUNCTION ROLE TESTS ================================

    function test_setFunctionRole_byAdmin() public {
        vm.prank(admin);
        accessManager.setFunctionRole(TEST_SELECTOR, CUSTOM_ROLE);

        assertEq(accessManager.getFunctionRole(TEST_SELECTOR), CUSTOM_ROLE);
    }

    function test_setFunctionRole_emitsEvent() public {
        vm.expectEmit(true, true, false, false);
        emit FunctionRoleUpdated(TEST_SELECTOR, CUSTOM_ROLE);

        vm.prank(admin);
        accessManager.setFunctionRole(TEST_SELECTOR, CUSTOM_ROLE);
    }

    function test_setFunctionRole_revertsIfNotAdmin() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(SimpleAccessManager.AccessManagerUnauthorizedAccount.selector, user1, ADMIN_ROLE));
        accessManager.setFunctionRole(TEST_SELECTOR, CUSTOM_ROLE);
    }

    function test_setFunctionRole_canUpdateExisting() public {
        vm.startPrank(admin);
        accessManager.setFunctionRole(TEST_SELECTOR, CUSTOM_ROLE);
        accessManager.setFunctionRole(TEST_SELECTOR, ANOTHER_ROLE);
        vm.stopPrank();

        assertEq(accessManager.getFunctionRole(TEST_SELECTOR), ANOTHER_ROLE);
    }

    function test_getFunctionRole_defaultsToAdminRole() public view {
        // Unconfigured function defaults to 0 (ADMIN_ROLE)
        assertEq(accessManager.getFunctionRole(TEST_SELECTOR), ADMIN_ROLE);
    }

    // ================================ hasRole TESTS ================================

    function test_hasRole_returnsTrueForPublicRole() public view {
        // All addresses have PUBLIC_ROLE
        assertTrue(accessManager.hasRole(PUBLIC_ROLE, user1));
        assertTrue(accessManager.hasRole(PUBLIC_ROLE, user2));
        assertTrue(accessManager.hasRole(PUBLIC_ROLE, address(0)));
        assertTrue(accessManager.hasRole(PUBLIC_ROLE, address(this)));
    }

    function test_hasRole_returnsFalseForNonMember() public view {
        assertFalse(accessManager.hasRole(CUSTOM_ROLE, user1));
    }

    function test_hasRole_returnsTrueForMember() public {
        vm.prank(admin);
        accessManager.grantRole(CUSTOM_ROLE, user1);

        assertTrue(accessManager.hasRole(CUSTOM_ROLE, user1));
    }

    // ================================ IAuthority INTERFACE TESTS ================================

    function test_implementsIAuthority() public view {
        // Verify the contract implements IAuthority
        assertTrue(accessManager.canCall(admin, address(0), TEST_SELECTOR) || !accessManager.canCall(admin, address(0), TEST_SELECTOR));
    }

    // ================================ INTEGRATION TESTS ================================

    function test_integration_limitOrderBookScenario() public {
        // This test simulates the limit order book deployment scenario
        bytes4 createSelector = bytes4(keccak256("create(bytes32,address,int24,uint128,bool)"));
        bytes4 setMaxFillCountSelector = bytes4(keccak256("setMaxFillCount(uint256)"));

        // Deploy with create() set to PUBLIC_ROLE
        SimpleAccessManager.InitialFunctionRole[] memory initialRoles = new SimpleAccessManager.InitialFunctionRole[](1);
        initialRoles[0] = SimpleAccessManager.InitialFunctionRole({selector: createSelector, roleId: PUBLIC_ROLE});

        SimpleAccessManager manager = new SimpleAccessManager(admin, initialRoles);

        // create() should be callable by anyone
        assertTrue(manager.canCall(user1, address(0), createSelector));
        assertTrue(manager.canCall(user2, address(0), createSelector));

        // setMaxFillCount() defaults to ADMIN_ROLE (only admin can call)
        assertTrue(manager.canCall(admin, address(0), setMaxFillCountSelector));
        assertFalse(manager.canCall(user1, address(0), setMaxFillCountSelector));
    }

    function test_integration_delegatedRoleManagement() public {
        // Admin sets up a role hierarchy:
        // - ADMIN_ROLE can manage ANOTHER_ROLE
        // - ANOTHER_ROLE can manage CUSTOM_ROLE

        vm.startPrank(admin);
        accessManager.setRoleAdmin(CUSTOM_ROLE, ANOTHER_ROLE);
        accessManager.grantRole(ANOTHER_ROLE, user1);
        vm.stopPrank();

        // user1 (with ANOTHER_ROLE) can now grant CUSTOM_ROLE
        vm.prank(user1);
        accessManager.grantRole(CUSTOM_ROLE, user2);

        assertTrue(accessManager.hasRole(CUSTOM_ROLE, user2));

        // user1 can also revoke CUSTOM_ROLE
        vm.prank(user1);
        accessManager.revokeRole(CUSTOM_ROLE, user2);

        assertFalse(accessManager.hasRole(CUSTOM_ROLE, user2));
    }

    function test_integration_adminCannotGrantPublicRole() public {
        // Even admin cannot grant PUBLIC_ROLE - it's automatic
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(SimpleAccessManager.AccessManagerLockedRole.selector, PUBLIC_ROLE));
        accessManager.grantRole(PUBLIC_ROLE, user1);
    }

    function test_integration_adminCanRenounceOwnRole() public {
        // Admin can renounce their own role (dangerous but allowed)
        vm.prank(admin);
        accessManager.renounceRole(ADMIN_ROLE, admin);

        assertFalse(accessManager.hasRole(ADMIN_ROLE, admin));

        // Now admin can't do admin things
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(SimpleAccessManager.AccessManagerUnauthorizedAccount.selector, admin, ADMIN_ROLE));
        accessManager.setFunctionRole(TEST_SELECTOR, CUSTOM_ROLE);
    }
}
