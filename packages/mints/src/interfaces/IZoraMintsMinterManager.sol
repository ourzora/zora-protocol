// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IZoraMints1155} from "../interfaces/IZoraMints1155.sol";

interface IZoraMintsMinterManager {
    /**
     * @dev Mints the currently mintable ETH-based token and sends it to the specified recipient.
     *      The total value sent must match the product of the currently mintable ETH token's price and the quantity to mint.
     * @param quantity The quantity of tokens to mint.
     * @param recipient The address to receive the minted tokens.
     * @return The ID of the token that was minted.
     */
    function mintWithEth(uint256 quantity, address recipient) external payable returns (uint256);

    /// @notice Retrieves the price in ETH of the currently mintable ETH-based token.
    function getEthPrice() external view returns (uint256);

    /// @notice Gets the token id of the current mintable ETH-based token.
    function mintableEthToken() external view returns (uint256);

    function zoraMints1155() external view returns (IZoraMints1155);
}
