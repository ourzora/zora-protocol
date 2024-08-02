// spdx-license-identifier: MIT
pragma solidity ^0.8.17;

import {IImmutableCreate2Factory} from "../interfaces/IImmutableCreate2Factory.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";

library ImmutableCreate2FactoryUtils {
    IImmutableCreate2Factory public constant IMMUTABLE_CREATE2_FACTORY = IImmutableCreate2Factory(0x0000000000FFe8B47B3e2130213B802212439497);

    bytes32 constant IMMUTABLE_CREATE_2_FRIENDLY_SALT = bytes32(0x0000000000000000000000000000000000000000000000000000000000000000);

    function saltWithAddressInFirst20Bytes(address addressToMakeSaltWith, uint256 suffix) internal pure returns (bytes32) {
        uint256 shifted = uint256(uint160(address(addressToMakeSaltWith))) << 96;

        // shifted on the left, suffix on the right:

        return bytes32(shifted | suffix);
    }

    /// Checks if a contract has been deployed at a determinstic address based on the sale using safe create 2, and if it hasnt been, deploys it
    /// @param salt The salt to use for the create 2 address
    /// @param creationCode The creation code to create with
    function safeCreate2OrGetExisting(bytes32 salt, bytes memory creationCode) internal returns (address) {
        address computedAddress = Create2.computeAddress(salt, keccak256(creationCode), address(IMMUTABLE_CREATE2_FACTORY));

        // if hasn't been created, create it
        if (computedAddress.code.length == 0) {
            IMMUTABLE_CREATE2_FACTORY.safeCreate2(salt, creationCode);
        }

        return computedAddress;
    }

    function safeCreate2OrGetExistingWithFriendlySalt(bytes memory creationCode) internal returns (address) {
        return safeCreate2OrGetExisting(IMMUTABLE_CREATE_2_FRIENDLY_SALT, creationCode);
    }

    function immutableCreate2Address(bytes memory creationCode) internal pure returns (address) {
        return immutableCreate2Address(IMMUTABLE_CREATE_2_FRIENDLY_SALT, creationCode);
    }

    function immutableCreate2Address(bytes32 salt, bytes memory creationCode) internal pure returns (address) {
        return Create2.computeAddress(salt, keccak256(creationCode), address(IMMUTABLE_CREATE2_FACTORY));
    }
}
