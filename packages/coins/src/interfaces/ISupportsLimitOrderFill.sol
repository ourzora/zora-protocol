// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @title ISupportsLimitOrderFill
/// @notice Marker interface for hooks that handle limit order filling in their afterSwap
/// @dev Hooks implementing this interface should handle zoraLimitOrderBook.fill() in afterSwap.
///      Use ERC165's supportsInterface to declare support: supportsInterface(type(ISupportsLimitOrderFill).interfaceId)

interface ISupportsLimitOrderFill {
    function supportsLimitOrderFill() external pure returns (bool);
}
