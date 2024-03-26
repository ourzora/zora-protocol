// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/// @notice The set of public functions on a Zora 1155 contract that are called by the ERC20 minter contract
interface IZora1155 {
    function createReferrals(uint256 tokenId) external view returns (address);

    function firstMinters(uint256 tokenId) external view returns (address);

    function getCreatorRewardRecipient(uint256 tokenId) external view returns (address);

    function adminMint(address recipient, uint256 tokenId, uint256 quantity, bytes memory data) external;
}
