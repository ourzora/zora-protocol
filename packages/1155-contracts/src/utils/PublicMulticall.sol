// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/utils/Address.sol";

/// @title PublicMulticall
/// @notice Contract for executing a batch of function calls on this contract
abstract contract PublicMulticall {
    /**
     * @notice Receives and executes a batch of function calls on this contract.
     */
    function multicall(bytes[] calldata data) public virtual returns (bytes[] memory results) {
        results = new bytes[](data.length);
        for (uint256 i = 0; i < data.length; i++) {
            results[i] = Address.functionDelegateCall(address(this), data[i]);
        }
    }

    /**
     * @notice Receives and executes a batch of function calls on this contract.
     */
    function _multicallInternal(bytes[] memory data) internal virtual returns (bytes[] memory results) {
        results = new bytes[](data.length);
        for (uint256 i = 0; i < data.length; i++) {
            results[i] = Address.functionDelegateCall(address(this), data[i]);
        }
    }
}
