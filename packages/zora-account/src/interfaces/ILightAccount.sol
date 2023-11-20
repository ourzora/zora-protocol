// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface ILightAccount {

    /**
    * @notice Emitted when this account is first initialized
    * @param entryPoint The entry point
    * @param owner The initial owner
    *
    **/
    event LightAccountInitialized(IEntryPoint indexed entryPoint, adress indexed owner);

    /**
    * @dev The length of the array does not match the expected size
    **/
    error ArrayLengthMismatch();

    /**
    * @dev The new owner is not a valid owner (e.g. `address(0)`, the
    account itself, or the current owner.
    **/
    error InvalidOwner(address owner);

    /**
    * @dev The caller is not authorized.
    */
    error NotAuthorized(address caller);



}