// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @dev Provides tracking nonces for addresses. Nonces can be in any order and just need to be unique.
 */
abstract contract UnorderedNonces {
    /**
     * @dev The nonce used for an `account` is not the expected current nonce.
     */
    error InvalidAccountNonce(address account, uint256 currentNonce);

    mapping(address account => mapping(uint256 => bool)) private _nonces;

    /**
     * @dev Returns the next unused nonce for an address.
     */
    function nonceUsed(address owner, uint256 nonce) public view virtual returns (bool) {
        return _nonces[owner][nonce];
    }

    /**
     * @dev Same as {_useNonce} but checking that `nonce` passed in is valid.
     */
    function _useCheckedNonce(address owner, uint256 nonce) internal virtual {
        if (_nonces[owner][nonce]) {
            revert InvalidAccountNonce(owner, nonce);
        }
        _nonces[owner][nonce] = true;
    }
}
