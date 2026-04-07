// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ISwapRouter} from "../../src/interfaces/ISwapRouter.sol";

/// @notice Mock V3 SwapRouter for non-forked tests
/// @dev This mock doesn't implement any actual swap logic - it's just to satisfy constructor requirements
contract MockSwapRouter is ISwapRouter {
    /// @notice Mock implementation - reverts since V3 swaps shouldn't be called in non-forked tests
    function exactInputSingle(ExactInputSingleParams calldata) external payable returns (uint256) {
        revert("MockSwapRouter: V3 swaps not supported in non-forked tests");
    }

    /// @notice Mock implementation - reverts since V3 swaps shouldn't be called in non-forked tests
    function exactInput(ExactInputParams calldata) external payable returns (uint256) {
        revert("MockSwapRouter: V3 swaps not supported in non-forked tests");
    }

    /// @notice Mock implementation - reverts since V3 swaps shouldn't be called in non-forked tests
    function exactOutputSingle(ExactOutputSingleParams calldata) external payable returns (uint256) {
        revert("MockSwapRouter: V3 swaps not supported in non-forked tests");
    }

    /// @notice Mock implementation - reverts since V3 swaps shouldn't be called in non-forked tests
    function exactOutput(ExactOutputParams calldata) external payable returns (uint256) {
        revert("MockSwapRouter: V3 swaps not supported in non-forked tests");
    }

    /// @notice Mock implementation of V3 callback - reverts since V3 swaps shouldn't be called in non-forked tests
    function uniswapV3SwapCallback(int256, int256, bytes calldata) external pure {
        revert("MockSwapRouter: V3 swaps not supported in non-forked tests");
    }
}
