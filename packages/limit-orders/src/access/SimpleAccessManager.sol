// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IAuthority} from "@openzeppelin/contracts/access/manager/IAuthority.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";

/**
 * @title SimpleAccessManager
 * @author Zora
 * @notice A simplified single-contract access manager providing role-based access control
 * without time-based validation.
 *
 * @dev This contract is designed to manage access for a single target contract by mapping
 * function selectors directly to required roles. It implements the IAuthority interface
 * for compatibility with SimpleAccessManaged contracts.
 *
 * Key features:
 * - Maps function selectors to roles (selector -> roleId)
 * - Immediate role grants/revokes (no delays)
 * - PUBLIC_ROLE grants access to all addresses
 * - ADMIN_ROLE (role 0) can configure function roles and manage other roles
 * - Each role can have a custom admin role for delegation
 *
 * This is intentionally simpler than OpenZeppelin's AccessManager:
 * - No execution delays or scheduled operations
 * - No guardian role
 * - No target address tracking (single-contract authority)
 */
contract SimpleAccessManager is Context, IAuthority {
    /// @notice The admin role identifier (0). Members can configure function roles and grant other roles.
    uint64 public constant ADMIN_ROLE = type(uint64).min;

    /// @notice The public role identifier (max uint64). All addresses implicitly have this role.
    uint64 public constant PUBLIC_ROLE = type(uint64).max;

    /// @notice Configuration for setting a function's required role at deployment
    /// @param selector The function selector to configure
    /// @param roleId The role required to call the function
    struct InitialFunctionRole {
        bytes4 selector;
        uint64 roleId;
    }

    /// @dev Maps function selector to the role required to call it
    mapping(bytes4 selector => uint64 roleId) private _functionRoles;

    /// @dev Maps role to its members
    mapping(uint64 roleId => mapping(address user => bool isMember)) private _roleMembers;

    /// @dev Maps role to its admin role (the role that can grant/revoke it)
    mapping(uint64 roleId => uint64 admin) private _roleAdmins;

    /// @notice Emitted when a role is granted to an account
    /// @param roleId The role that was granted
    /// @param account The account that received the role
    event RoleGranted(uint64 indexed roleId, address indexed account);

    /// @notice Emitted when a role is revoked from an account
    /// @param roleId The role that was revoked
    /// @param account The account that lost the role
    event RoleRevoked(uint64 indexed roleId, address indexed account);

    /// @notice Emitted when a role's admin is changed
    /// @param roleId The role whose admin changed
    /// @param admin The new admin role
    event RoleAdminChanged(uint64 indexed roleId, uint64 indexed admin);

    /// @notice Emitted when a function's required role is updated
    /// @param selector The function selector that was configured
    /// @param roleId The new required role
    event FunctionRoleUpdated(bytes4 indexed selector, uint64 indexed roleId);

    /// @notice Thrown when the initial admin address is invalid (zero address)
    /// @param initialAdmin The invalid admin address provided
    error AccessManagerInvalidInitialAdmin(address initialAdmin);

    /// @notice Thrown when an account lacks the required role
    /// @param account The account that attempted the action
    /// @param roleId The role that was required
    error AccessManagerUnauthorizedAccount(address account, uint64 roleId);

    /// @notice Thrown when attempting to modify a locked role (ADMIN_ROLE or PUBLIC_ROLE)
    /// @param roleId The locked role that was targeted
    error AccessManagerLockedRole(uint64 roleId);

    /// @dev Restricts function access to accounts with ADMIN_ROLE.
    modifier onlyAdmin() {
        if (!hasRole(ADMIN_ROLE, _msgSender())) {
            revert AccessManagerUnauthorizedAccount(_msgSender(), ADMIN_ROLE);
        }
        _;
    }

    /// @dev Restricts function access to accounts that have the admin role for the specified role.
    /// @param roleId The role whose admin is required to call the function
    modifier onlyRoleAdmin(uint64 roleId) {
        uint64 adminRole = getRoleAdmin(roleId);
        if (!hasRole(adminRole, _msgSender())) {
            revert AccessManagerUnauthorizedAccount(_msgSender(), adminRole);
        }
        _;
    }

    /// @notice Initializes the access manager with an admin and optional function role configurations.
    /// @dev The initial admin is granted ADMIN_ROLE immediately. Initial function roles allow
    /// configuring access permissions at deployment time without additional transactions.
    /// @param initialAdmin The address that will receive ADMIN_ROLE (cannot be zero address)
    /// @param initialFunctionRoles Array of selector-to-role mappings to configure at deployment
    constructor(address initialAdmin, InitialFunctionRole[] memory initialFunctionRoles) {
        if (initialAdmin == address(0)) {
            revert AccessManagerInvalidInitialAdmin(address(0));
        }

        // Admin is active immediately
        _grantRole(ADMIN_ROLE, initialAdmin);

        // Set up initial function roles
        for (uint256 i = 0; i < initialFunctionRoles.length; ++i) {
            _setFunctionRole(initialFunctionRoles[i].selector, initialFunctionRoles[i].roleId);
        }
    }

    // =================================================== IAuthority ====================================================

    /// @inheritdoc IAuthority
    /// @notice Checks if a caller is authorized to invoke a function.
    /// @dev The target parameter is ignored since this is a single-contract authority.
    /// Returns true if the caller has the role required for the selector, or if the
    /// selector is mapped to PUBLIC_ROLE (which all addresses implicitly have).
    /// @param caller The address attempting to call the function
    /// @param selector The function selector being called
    /// @return True if the caller is authorized to call the function
    function canCall(
        address caller,
        address,
        /* target */
        bytes4 selector
    ) external view override returns (bool) {
        uint64 roleId = _functionRoles[selector];
        return hasRole(roleId, caller);
    }

    // =================================================== GETTERS ====================================================

    /// @notice Returns the role required to call a specific function.
    /// @dev If no role has been set for the selector, returns 0 (ADMIN_ROLE), meaning
    /// only admins can call unconfigured functions by default.
    /// @param selector The function selector to query
    /// @return The role ID required to call the function
    function getFunctionRole(bytes4 selector) public view returns (uint64) {
        return _functionRoles[selector];
    }

    /// @notice Returns the admin role for a given role.
    /// @dev The admin role is the role that can grant/revoke the specified role.
    /// If no admin has been set, returns 0 (ADMIN_ROLE).
    /// @param roleId The role to query the admin for
    /// @return The admin role ID that can manage the specified role
    function getRoleAdmin(uint64 roleId) public view returns (uint64) {
        return _roleAdmins[roleId];
    }

    /// @notice Checks if an account has a specific role.
    /// @dev PUBLIC_ROLE always returns true for any account. For other roles,
    /// returns true only if the account has been explicitly granted the role.
    /// @param roleId The role to check
    /// @param account The account to check
    /// @return True if the account has the role
    function hasRole(uint64 roleId, address account) public view returns (bool) {
        if (roleId == PUBLIC_ROLE) {
            return true;
        }
        return _roleMembers[roleId][account];
    }

    // =============================================== ROLE MANAGEMENT ===============================================

    /// @notice Grants a role to an account.
    /// @dev Only callable by accounts that have the admin role for the specified role.
    /// Emits {RoleGranted} if the account did not already have the role.
    /// @param roleId The role to grant
    /// @param account The account to receive the role
    function grantRole(uint64 roleId, address account) public onlyRoleAdmin(roleId) {
        _grantRole(roleId, account);
    }

    /// @notice Revokes a role from an account.
    /// @dev Only callable by accounts that have the admin role for the specified role.
    /// Emits {RoleRevoked} if the account had the role.
    /// @param roleId The role to revoke
    /// @param account The account to lose the role
    function revokeRole(uint64 roleId, address account) public onlyRoleAdmin(roleId) {
        _revokeRole(roleId, account);
    }

    /// @notice Allows an account to renounce a role it has.
    /// @dev The callerConfirmation parameter must match msg.sender to prevent accidental
    /// role renunciation. Emits {RoleRevoked} if the account had the role.
    /// @param roleId The role to renounce
    /// @param callerConfirmation Must be msg.sender's address as confirmation
    function renounceRole(uint64 roleId, address callerConfirmation) public {
        if (callerConfirmation != _msgSender()) {
            revert AccessManagerUnauthorizedAccount(_msgSender(), roleId);
        }
        _revokeRole(roleId, callerConfirmation);
    }

    /// @notice Sets the admin role for a given role.
    /// @dev Only callable by accounts with ADMIN_ROLE. Cannot modify the admin of
    /// ADMIN_ROLE or PUBLIC_ROLE. Emits {RoleAdminChanged}.
    /// @param roleId The role to set the admin for
    /// @param admin The new admin role ID
    function setRoleAdmin(uint64 roleId, uint64 admin) public onlyAdmin {
        if (roleId == ADMIN_ROLE || roleId == PUBLIC_ROLE) {
            revert AccessManagerLockedRole(roleId);
        }

        _roleAdmins[roleId] = admin;
        emit RoleAdminChanged(roleId, admin);
    }

    /// @dev Grants a role to an account without access control checks.
    /// @param roleId The role to grant (cannot be PUBLIC_ROLE)
    /// @param account The account to receive the role
    function _grantRole(uint64 roleId, address account) internal {
        if (roleId == PUBLIC_ROLE) {
            revert AccessManagerLockedRole(roleId);
        }

        if (!_roleMembers[roleId][account]) {
            _roleMembers[roleId][account] = true;
            emit RoleGranted(roleId, account);
        }
    }

    /// @dev Revokes a role from an account without access control checks.
    /// @param roleId The role to revoke (cannot be PUBLIC_ROLE)
    /// @param account The account to lose the role
    function _revokeRole(uint64 roleId, address account) internal {
        if (roleId == PUBLIC_ROLE) {
            revert AccessManagerLockedRole(roleId);
        }

        if (_roleMembers[roleId][account]) {
            _roleMembers[roleId][account] = false;
            emit RoleRevoked(roleId, account);
        }
    }

    // ============================================= FUNCTION MANAGEMENT ==============================================

    /// @notice Sets the role required to call a specific function.
    /// @dev Only callable by accounts with ADMIN_ROLE. Set to PUBLIC_ROLE to make a
    /// function callable by anyone. Emits {FunctionRoleUpdated}.
    /// @param selector The function selector to configure
    /// @param roleId The role that will be required to call the function
    function setFunctionRole(bytes4 selector, uint64 roleId) public onlyAdmin {
        _setFunctionRole(selector, roleId);
    }

    /// @dev Sets a function's required role without access control checks.
    /// @param selector The function selector to configure
    /// @param roleId The role that will be required to call the function
    function _setFunctionRole(bytes4 selector, uint64 roleId) internal {
        _functionRoles[selector] = roleId;
        emit FunctionRoleUpdated(selector, roleId);
    }
}
