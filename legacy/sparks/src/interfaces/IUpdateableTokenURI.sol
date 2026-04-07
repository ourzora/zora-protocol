// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IUpdateableTokenURI {
    /**
     * @dev Emitted when the contract URI and base URI are updated.
     */
    event URIsUpdated(string contractURI, string baseURI);

    function notifyURIsUpdated(string calldata contractURI, string calldata baseURI) external;
    function notifyUpdatedTokenURI(string calldata uri, uint256 tokenId) external;
}
