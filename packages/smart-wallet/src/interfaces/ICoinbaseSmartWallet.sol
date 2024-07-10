// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IAccount} from "./IAccount.sol";
import {UserOperation} from "./UserOperation.sol";
import {IUUPSUpgradeable} from "./IUUPSUpgradeable.sol";

import {IERC1271} from "./IERC1271.sol";
import {IMultiOwnable} from "./IMultiOwnable.sol";

/// @title Coinbase Smart Wallet - extracted interface
///
/// @notice ERC-4337-compatible smart account, based on Solady's ERC4337 account implementation
///         with inspiration from Alchemy's LightAccount and Daimo's DaimoAccount.
/// @dev This interface is the conversion of the CoinbaseSmartWallet.sol contract into an interface,
// with all of its inherited classes converted into interfaces and included in this repo to minimize external dependencies.
// The original contract was located at https://github.com/coinbase/smart-wallet/blob/6579faa7f7f7a7de75db92f93e92584764ae1aa2/src/CoinbaseSmartWallet.sol
///
/// @author Coinbase (https://github.com/coinbase/smart-wallet)
/// @author Solady (https://github.com/vectorized/solady/blob/main/src/accounts/ERC4337.sol)
interface ICoinbaseSmartWallet is IERC1271, IAccount, IMultiOwnable, IUUPSUpgradeable {
    /// @notice A wrapper struct used for signature validation so that callers
    ///         can identify the owner that signed.
    struct SignatureWrapper {
        /// @dev The index of the owner that signed, see `MultiOwnable.ownerAtIndex`
        uint256 ownerIndex;
        /// @dev If `MultiOwnable.ownerAtIndex` is an Ethereum address, this should be `abi.encodePacked(r, s, v)`
        ///      If `MultiOwnable.ownerAtIndex` is a external key, this should be `abi.encode(WebAuthnAuth)`.
        bytes signatureData;
    }

    /// @notice Represents a call to make.
    struct Call {
        /// @dev The address to call.
        address target;
        /// @dev The value to send when making the call.
        uint256 value;
        /// @dev The data of the call.
        bytes data;
    }

    /// @notice Thrown when `initialize` is called but the account already has had at least one owner.
    error Initialized();

    /// @notice Thrown when a call is passed to `executeWithoutChainIdValidation` that is not allowed by
    ///         `canSkipChainIdValidation`
    ///
    /// @param selector The selector of the call.
    error SelectorNotAllowed(bytes4 selector);

    /// @notice Thrown in validateUserOp if the key of `UserOperation.nonce` does not match the calldata.
    ///
    /// @dev Calls to `this.executeWithoutChainIdValidation` MUST use `REPLAYABLE_NONCE_KEY` and
    ///      calls NOT to `this.executeWithoutChainIdValidation` MUST NOT use `REPLAYABLE_NONCE_KEY`.
    ///
    /// @param key The invalid `UserOperation.nonce` key.
    error InvalidNonceKey(uint256 key);

    /// @notice Initializes the account with the `owners`.
    ///
    /// @dev Reverts if the account has had at least one owner, i.e. has been initialized.
    ///
    /// @param owners Array of initial owners for this account. Each item should be
    ///               an ABI encoded Ethereum address, i.e. 32 bytes with 12 leading 0 bytes,
    ///               or a 64 byte external key.
    function initialize(bytes[] calldata owners) external payable;

    /// @notice Executes `calls` on this account (i.e. self call).
    ///
    /// @dev Can only be called by the Entrypoint.
    /// @dev Reverts if the given call is not authorized to skip the chain ID validtion.
    /// @dev `validateUserOp()` will recompute the `userOpHash` without the chain ID before validating
    ///      it if the `UserOperation.calldata` is calling this function. This allows certain UserOperations
    ///      to be replayed for all accounts sharing the same address across chains. E.g. This may be
    ///      useful for syncing owner changes.
    ///
    /// @param calls An array of calldata to use for separate self calls.
    function executeWithoutChainIdValidation(bytes[] calldata calls) external payable;

    /// @notice Executes the given call from this account.
    ///
    /// @dev Can only be called by the Entrypoint or an owner of this account (including itself).
    ///
    /// @param target The address to call.
    /// @param value  The value to send with the call.
    /// @param data   The data of the call.
    function execute(address target, uint256 value, bytes calldata data) external;

    /// @notice Executes batch of `Call`s.
    ///
    /// @dev Can only be called by the Entrypoint or an owner of this account (including itself).
    ///
    /// @param calls The list of `Call`s to execute.
    function executeBatch(Call[] calldata calls) external;

    /// @notice Returns the address of the EntryPoint v0.6.
    ///
    /// @return The address of the EntryPoint v0.6
    function entryPoint() external view returns (address);

    /// @notice Computes the hash of the `UserOperation` in the same way as EntryPoint v0.6, but
    ///         leaves out the chain ID.
    ///
    /// @dev This allows accounts to sign a hash that can be used on many chains.
    ///
    /// @param userOp The `UserOperation` to compute the hash for.
    ///
    /// @return The `UserOperation` hash, which does not depend on chain ID.
    function getUserOpHashWithoutChainId(UserOperation calldata userOp) external view returns (bytes32);

    /// @notice Returns the implementation of the ERC1967 proxy.
    ///
    /// @return $ The address of implementation contract.
    function implementation() external view returns (address $);

    /// @notice Returns whether `functionSelector` can be called in `executeWithoutChainIdValidation`.
    ///
    /// @param functionSelector The function selector to check.
    ////
    /// @return `true` is the function selector is allowed to skip the chain ID validation, else `false`.
    function canSkipChainIdValidation(bytes4 functionSelector) external pure returns (bool);
}
