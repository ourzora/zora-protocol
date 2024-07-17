// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IZoraSparksURIManager {
    function uri(uint256 tokenId) external view returns (string memory);

    function contractURI() external view returns (string memory);

    event URIsUpdated(string contractURI, string baseURI);
}
