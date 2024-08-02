// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IReduceSupply {
    /// @notice Reduces the max supply of a token
    /// @param tokenId The token to reduce the supply of
    /// @param newMaxSupply The new max supply of the token
    function reduceSupply(uint256 tokenId, uint256 newMaxSupply) external;
}
