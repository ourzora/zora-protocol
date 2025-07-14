// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {TokenConfig, Redemption} from "../ZoraSparksTypes.sol";
import {IZoraSparks1155Errors} from "./IZoraSparks1155Errors.sol";
import {IUpdateableTokenURI} from "./IUpdateableTokenURI.sol";

/**
 * @title IZoraSparks1155 interface
 * @dev The IZoraSparks1155 interface defines an implementation of the ERC1155 standard with additional features:
 *
 * Accounts can mint new tokens by sending ETH to the contract based on the current mintable token's
 * price in ETH. The amount of ETH sent must match the total price for the quantity of tokens being minted.
 * The price of a token cannot be changed, ensuring that the value of each token is fixed.
 *
 * Accounts can also redeem tokens by burning them and receiving their equivalent value in ETH.
 * The amount of ETH received is based on the quantity of tokens burned and the price per token.
 *
 */
interface IZoraSparks1155 is IZoraSparks1155Errors, IERC1155 {
    /// @notice Event emitted when a mint token is created
    /// @param tokenId The ID of the token
    /// @param price The price of the token
    /// @param tokenAddress The address of the token
    event TokenCreated(uint256 indexed tokenId, uint256 indexed price, address indexed tokenAddress);

    /**
     * @dev Redeems the equivalent value of a specified quantity of tokens and sends it to the recipient.
     *      This function can only be called by the current owner of the tokens. It unwraps the value of the tokens,
     *      sends it to the recipient, and then burns the tokens.
     * @param tokenId The ID of the token to redeem.
     * @param quantity The quantity of tokens to redeem.
     * @param recipient The address to receive the unwrapped funds.
     */
    function redeem(uint tokenId, uint quantity, address recipient) external returns (Redemption memory);

    function redeemBatch(uint[] calldata tokenIds, uint[] calldata quantities, address recipient) external returns (Redemption[] memory redemptions);

    // only callable by sparks manager
    function mintTokenWithEth(uint256 tokenId, uint256 quantity, address recipient, bytes memory data) external payable;

    // only callable by sparks manager
    function mintTokenWithERC20(uint256 tokenId, address tokenAddress, uint quantity, address recipient, bytes memory data) external;

    function createToken(uint256 tokenId, TokenConfig calldata tokenConfig) external;

    /**
     * Gets if token with the specific id has been created
     * @param tokenId The ID of the token to check.
     */
    function tokenExists(uint tokenId) external view returns (bool);

    /// @notice Helper to get the user's total balance of sparks
    /// @param user User to query for balances
    function balanceOfAccount(address user) external returns (uint256);

    /**
     * Gets the price of a token
     * @param tokenId The id of the token to check
     */
    function tokenPrice(uint tokenId) external view returns (uint);

    function getTokenConfig(uint256 tokeId) external returns (TokenConfig memory);

    function MINIMUM_ETH_PRICE() external view returns (uint256);

    function MINIMUM_ERC20_PRICE() external view returns (uint256);
}
