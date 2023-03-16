// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

/// @notice Interface for types used across the ZoraCreator1155 contract
interface IZoraCreator1155TypesV1 {
    /// @notice Type for token data storage
    struct TokenData {
        string uri;
        uint256 maxSupply;
        uint256 totalMinted;
    }
}
