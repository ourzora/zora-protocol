// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {ECDSAUpgradeable} from "@zoralabs/openzeppelin-contracts-upgradeable/contracts/utils/cryptography/ECDSAUpgradeable.sol";

/** Simple implementation of an AA contract with a single owner */
contract SimpleAA {
    bytes4 internal constant MAGIC_VALUE = bytes4(keccak256("isValidSignature(bytes32,bytes)"));
    address immutable owner;

    constructor(address _owner) {
        owner = _owner;
    }

    function isValidSignature(bytes32 _messageHash, bytes memory _signature) public view returns (bytes4 magicValue) {
        address signatory = ECDSAUpgradeable.recover(_messageHash, _signature);

        if (signatory == owner) {
            return MAGIC_VALUE;
        }

        return bytes4(0);
    }

    receive() external payable {}
}
