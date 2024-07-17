// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IZoraSparks1155} from "../interfaces/IZoraSparks1155.sol";

interface IZoraSparksMinterManager {
    /**
     * @dev Mints an ETH-based token and sends it to the specified recipient.
     *      The total value sent must match the product of the mintable ETH token's price and the quantity to mint.
     * @param quantity The quantity of tokens to mint.
     * @param tokenId The ID of the token to mint.
     * @param recipient The address to receive the minted tokens.
     */
    function mintWithEth(uint256 quantity, uint256 tokenId, address recipient) external payable;

    function zoraSparks1155() external view returns (IZoraSparks1155);
}
