// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

// interface extracted from: https://github.com/coinbase/smart-wallet/blob/main/src/MultiOwnable.sol

/// @notice Storage layout used by this contract.
///
/// @custom:storage-location erc7201:coinbase.storage.MultiOwnable
struct MultiOwnableStorage {
    /// @dev Tracks the index of the next owner to add.
    uint256 nextOwnerIndex;
    /// @dev Tracks number of owners that have been removed.
    uint256 removedOwnersCount;
    /// @dev Maps index to owner bytes, used to idenfitied owners via a uint256 index.
    ///
    ///      Some uses—-such as signature validation for secp256r1 external key owners—-
    ///      requires the caller to assert the external key of the caller. To economize calldata,
    ///      we allow an index to identify an owner, so that the full owner bytes do
    ///      not need to be passed.
    ///
    ///      The `owner` bytes should either be
    ///         - An ABI encoded Ethereum address
    ///         - An ABI encoded external key
    mapping(uint256 index => bytes owner) ownerAtIndex;
    /// @dev Mapping of bytes to booleans indicating whether or not
    ///      bytes_ is an owner of this contract.
    mapping(bytes bytes_ => bool isOwner_) isOwner;
}

/// @title Multi Ownable
///
/// @notice Auth contract allowing multiple owners, each identified as bytes.
///
/// @author Coinbase (https://github.com/coinbase/smart-wallet)
interface IMultiOwnable {
    /// @notice Thrown when the `msg.sender` is not an owner and is trying to call a privileged function.
    error Unauthorized();

    /// @notice Thrown when trying to add an already registered owner.
    ///
    /// @param owner The owner bytes.
    error AlreadyOwner(bytes owner);

    /// @notice Thrown when trying to remove an owner from an index that is empty.
    ///
    /// @param index The targeted index for removal.
    error NoOwnerAtIndex(uint256 index);

    /// @notice Thrown when `owner` argument does not match owner found at index.
    ///
    /// @param index         The index of the owner to be removed.
    /// @param expectedOwner The owner passed in the remove call.
    /// @param actualOwner   The actual owner at `index`.
    error WrongOwnerAtIndex(uint256 index, bytes expectedOwner, bytes actualOwner);

    /// @notice Thrown when a provided owner is neither 64 bytes long (for external key)
    ///         nor a ABI encoded address.
    ///
    /// @param owner The invalid owner.
    error InvalidOwnerBytesLength(bytes owner);

    /// @notice Thrown if a provided owner is 32 bytes long but does not fit in an `address` type.
    ///
    /// @param owner The invalid owner.
    error InvalidEthereumAddressOwner(bytes owner);

    /// @notice Thrown when removeOwnerAtIndex is called and there is only one current owner.
    error LastOwner();

    /// @notice Thrown when removeLastOwner is called and there is more than one current owner.
    ///
    /// @param ownersRemaining The number of current owners.
    error NotLastOwner(uint256 ownersRemaining);

    /// @notice Emitted when a new owner is registered.
    ///
    /// @param index The owner index of the owner added.
    /// @param owner The owner added.
    event AddOwner(uint256 indexed index, bytes owner);

    /// @notice Emitted when an owner is removed.
    ///
    /// @param index The owner index of the owner removed.
    /// @param owner The owner removed.
    event RemoveOwner(uint256 indexed index, bytes owner);

    /// @notice Adds a new Ethereum-address owner.
    ///
    /// @param owner The owner address.
    function addOwnerAddress(address owner) external;

    /// @notice Adds a new external-key owner.
    ///
    /// @param x The owner external key x coordinate.
    /// @param y The owner external key y coordinate.
    function addOwnerPublicKey(bytes32 x, bytes32 y) external;

    /// @notice Removes owner at the given `index`.
    ///
    /// @dev Reverts if the owner is not registered at `index`.
    /// @dev Reverts if there is currently only one owner.
    /// @dev Reverts if `owner` does not match bytes found at `index`.
    ///
    /// @param index The index of the owner to be removed.
    /// @param owner The ABI encoded bytes of the owner to be removed.
    function removeOwnerAtIndex(uint256 index, bytes calldata owner) external;

    /// @notice Removes owner at the given `index`, which should be the only current owner.
    ///
    /// @dev Reverts if the owner is not registered at `index`.
    /// @dev Reverts if there is currently more than one owner.
    /// @dev Reverts if `owner` does not match bytes found at `index`.
    ///
    /// @param index The index of the owner to be removed.
    /// @param owner The ABI encoded bytes of the owner to be removed.
    function removeLastOwner(uint256 index, bytes calldata owner) external;

    /// @notice Checks if the given `account` address is registered as owner.
    ///
    /// @param account The account address to check.
    ///
    /// @return `true` if the account is an owner else `false`.
    function isOwnerAddress(address account) external view returns (bool);

    /// @notice Checks if the given `x`, `y` external key is registered as owner.
    ///
    /// @param x The external key x coordinate.
    /// @param y The external key y coordinate.
    ///
    /// @return `true` if the account is an owner else `false`.
    function isOwnerPublicKey(bytes32 x, bytes32 y) external view returns (bool);

    /// @notice Checks if the given `account` bytes is registered as owner.
    ///
    /// @param account The account, should be ABI encoded address or external key.
    ///
    /// @return `true` if the account is an owner else `false`.
    function isOwnerBytes(bytes memory account) external view returns (bool);

    /// @notice Returns the owner bytes at the given `index`.
    ///
    /// @param index The index to lookup.
    ///
    /// @return The owner bytes (empty if no owner is registered at this `index`).
    function ownerAtIndex(uint256 index) external view returns (bytes memory);

    /// @notice Returns the next index that will be used to add a new owner.
    ///
    /// @return The next index that will be used to add a new owner.
    function nextOwnerIndex() external view returns (uint256);

    /// @notice Returns the current number of owners
    ///
    /// @return The current owner count
    function ownerCount() external view returns (uint256);

    /// @notice Tracks the number of owners removed
    ///
    /// @dev Used with `this.nextOwnerIndex` to avoid removing all owners
    ///
    /// @return The number of owners that have been removed.
    function removedOwnersCount() external view returns (uint256);
}
