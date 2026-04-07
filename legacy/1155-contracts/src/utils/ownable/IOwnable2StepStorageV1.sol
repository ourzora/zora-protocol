// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

abstract contract IOwnable2StepStorageV1 {
    /// @dev The address of the owner
    address internal _owner;

    /// @dev The address of the pending owner
    address internal _pendingOwner;

    /// @dev storage gap
    uint256[50] private __gap;
}
