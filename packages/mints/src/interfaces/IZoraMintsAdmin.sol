// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {TokenConfig} from "../ZoraMintsTypes.sol";

interface IZoraMintsAdmin {
    event DefaultMintableTokenSet(address tokenAddress, uint tokenId);

    /**
     * @dev Sets a specific ETH-based token as mintable. Restricted to admin.
     * @param tokenId The ID of the token to set as mintable.
     */
    function setDefaultMintable(address tokenAddress, uint tokenId) external;

    function createToken(uint256 tokenId, TokenConfig calldata tokenConfig, bool defaultMintable) external;
}
