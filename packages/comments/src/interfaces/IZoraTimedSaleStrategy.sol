// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IZoraTimedSaleStrategy {
    function mint(address mintTo, uint256 quantity, address collection, uint256 tokenId, address mintReferral, string calldata comment) external payable;

    /// @dev This is the SaleV1 style sale with a set end and start time and is used in both cases for storing key sale information
    struct SaleStorage {
        /// @notice The ERC20z address
        address payable erc20zAddress;
        /// @notice The sale start time
        uint64 saleStart;
        /// @notice The Uniswap pool address
        address poolAddress;
        /// @notice The sale end time
        uint64 saleEnd;
        /// @notice Boolean if the secondary market has been launched
        bool secondaryActivated;
    }

    /// @notice Returns the sale config for a given token
    /// @param collection The collection address
    /// @param tokenId The ID of the token to get the sale config for
    function sale(address collection, uint256 tokenId) external view returns (SaleStorage memory);
}
