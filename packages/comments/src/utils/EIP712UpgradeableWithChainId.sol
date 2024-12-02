// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/// Extension of EIP712Upgradeable that allows for messages to be signed on other chains.
abstract contract EIP712UpgradeableWithChainId is EIP712Upgradeable {
    bytes32 private constant TYPE_HASH = keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    /**
     * @dev Returns the domain separator for the current chain.
     */
    function _domainSeparatorV4(uint256 chainId) internal view returns (bytes32) {
        return _buildDomainSeparator(chainId);
    }

    function _buildDomainSeparator(uint256 chainId) private view returns (bytes32) {
        return keccak256(abi.encode(TYPE_HASH, _EIP712NameHash(), _EIP712VersionHash(), chainId, address(this)));
    }

    function _hashTypedDataV4(bytes32 structHash, uint256 chainId) internal view returns (bytes32) {
        return MessageHashUtils.toTypedDataHash(_domainSeparatorV4(chainId), structHash);
    }
}
