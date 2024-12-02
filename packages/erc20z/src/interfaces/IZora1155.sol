// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IZora1155 {
    struct TokenData {
        string uri;
        uint256 maxSupply;
        uint256 totalMinted;
    }

    function getTokenInfo(uint256 tokenId) external view returns (TokenData memory);

    function reduceSupply(uint256 tokenId, uint256 maxSupply) external;

    function createReferrals(uint256 tokenId) external view returns (address);

    function firstMinters(uint256 tokenId) external view returns (address);

    function getCreatorRewardRecipient(uint256 tokenId) external view returns (address);

    function addPermission(uint256 tokenId, address user, uint256 permissionBits) external;

    function adminMint(address recipient, uint256 tokenId, uint256 quantity, bytes memory data) external;

    function supportsInterface(bytes4 interfaceId) external view returns (bool);

    function uri(uint256 tokenId) external view returns (string memory);

    function setupNewToken(string memory tokenURI, uint256 maxSupply) external returns (uint256 tokenId);

    function callSale(uint256 tokenId, address salesConfig, bytes memory data) external;

    function balanceOf(address user, uint256 tokenId) external view returns (uint256);
}
