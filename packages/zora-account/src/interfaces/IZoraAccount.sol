// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {IEntryPoint} from "account-abstraction/contracts/interfaces/IEntryPoint.sol";

interface IZoraAccount is IERC1271 {
    /// @notice Emitted when a Zora account is first initialized
    /// @param entryPoint The entry point
    /// @param owner The initial owner
    /// @param sender The sender of the transaction
    event ZoraAccountInitialized(IEntryPoint indexed entryPoint, address indexed owner, address indexed sender);

    /// @notice Emitted when a Zora account receives ETH
    /// @param sender The sender of the ETH
    /// @param amount The amount of ETH received
    event ZoraAccountReceivedEth(address indexed sender, uint256 amount);

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

    /// @dev Reverts if a valid signer is not recovered for a given digest and signature
    /// @param digest The message digest
    /// @param signature The passed signature
    /// @param recoveredSigner The recovered signer
    error InvalidRecoveredSignature(bytes32 digest, bytes signature, address recoveredSigner);
}
