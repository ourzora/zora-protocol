// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IAuthority} from "@openzeppelin/contracts/access/manager/IAuthority.sol";

/**
 * @dev This contract module makes a contract "access managed", allowing an authority
 * contract to control access to specific functions.
 *
 * This is a simplified version of OpenZeppelin's AccessManaged that removes time-based
 * access control features (delays, scheduled operations) and only supports immediate
 * access checks.
 *
 * The authority is set during construction and can only be changed by the current authority.
 */
abstract contract SimpleAccessManaged {
    /// @dev Thrown when an unauthorized caller attempts to access a restricted function
    error AccessManagedUnauthorized();

    /// @dev Thrown when trying to set an invalid authority (e.g., not a contract)
    error AccessManagedInvalidAuthority(address authority);

    address private _authority;

    /// @dev Emitted when the authority is updated
    event AuthorityUpdated(address authority);

    /**
     * @dev Initializes the contract with an initial authority.
     * @param initialAuthority The address of the authority contract
     */
    constructor(address initialAuthority) {
        _setAuthority(initialAuthority);
    }

    /**
     * @dev Returns the current authority address.
     * @return The address of the authority contract
     */
    function authority() public view virtual returns (address) {
        return _authority;
    }

    /**
     * @dev Transfers control of the contract to a new authority.
     * Can only be called by the current authority.
     * @param newAuthority The address of the new authority contract
     */
    function setAuthority(address newAuthority) public virtual {
        if (msg.sender != authority()) {
            revert AccessManagedUnauthorized();
        }
        if (newAuthority.code.length == 0) {
            revert AccessManagedInvalidAuthority(newAuthority);
        }
        _setAuthority(newAuthority);
    }

    /**
     * @dev Internal function to set the authority without access checks.
     * @param newAuthority The address of the new authority contract
     */
    function _setAuthority(address newAuthority) internal virtual {
        _authority = newAuthority;
        emit AuthorityUpdated(newAuthority);
    }

    /**
     * @dev Internal function to check if a caller can execute a function.
     * Reverts with AccessManagedUnauthorized if the caller is not authorized.
     * @param selector The function selector being called
     */
    function _checkCanCall(bytes4 selector) internal view virtual {
        require(IAuthority(authority()).canCall(msg.sender, address(this), selector), AccessManagedUnauthorized());
    }
}
