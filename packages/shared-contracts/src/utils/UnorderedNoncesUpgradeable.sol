// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @dev Provides tracking nonces for addresses. Nonces can be in any order and just need to be unique.
 */
abstract contract UnorderedNoncesUpgradeable {
    /**
     * @dev The nonce used for an `account` is not the expected current nonce.
     */
    error InvalidAccountNonce(address account, bytes32 currentNonce);

    /// @custom:storage-location erc7201:unorderedNonces.storage.UnorderedNoncesStorage
    struct UnorderedNoncesStorage {
        mapping(address account => mapping(bytes32 => bool)) nonces;
    }

    // keccak256(abi.encode(uint256(keccak256("unorderedNonces.storage.UnorderedNoncesStorage")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant UNORDERED_NONCES_STORAGE_LOCATION = 0xc84b62be2e432010aa71cc1bbdba4c7b02245544521aa5beae20093c70622400;

    function _getUnorderedNoncesStorage() private pure returns (UnorderedNoncesStorage storage $) {
        assembly {
            $.slot := UNORDERED_NONCES_STORAGE_LOCATION
        }
    }

    /**
     * @dev Returns whether a nonce has been used for an address.
     */
    function nonceUsed(address owner, bytes32 nonce) public view virtual returns (bool) {
        return _getUnorderedNoncesStorage().nonces[owner][nonce];
    }

    /**
     * @dev Same as {_useNonce} but checking that `nonce` passed in is valid.
     */
    function _useCheckedNonce(address owner, bytes32 nonce) internal virtual {
        UnorderedNoncesStorage storage $ = _getUnorderedNoncesStorage();
        if ($.nonces[owner][nonce]) {
            revert InvalidAccountNonce(owner, nonce);
        }
        $.nonces[owner][nonce] = true;
    }
}
