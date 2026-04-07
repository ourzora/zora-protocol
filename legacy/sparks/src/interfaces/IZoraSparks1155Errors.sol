// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IZoraSparks1155Errors {
    /**
     * @dev No URI allowed for nonexistent token
     */
    error NoUriForNonexistentToken();

    /**
     * @dev Occurs when the amount of ETH sent to mint tokens does not match the required amount.
     * The required amount is the product of the quantity of tokens to mint and the price per token.
     */
    error IncorrectAmountSent();

    /**
     * @dev Occurs when an attempt is made to create a token with a token ID that has already been used.
     * Each token ID should be unique and can only be used once.
     */
    error TokenAlreadyCreated();

    /**
     * @dev Occurs when an operation is attempted on a token that does not exist.
     * This can occur when trying to set a non-existent token as mintable, or when trying to redeem a non-existent token.
     */
    error TokenDoesNotExist();

    /**
     * @dev Occurs when a transfer of ETH fails.
     * This can occur when trying to send the unwrapped value of redeemed tokens to a recipient.
     */
    error ETHTransferFailed();

    /**
     * @dev Occurs when an attempt is made to set the price of a token to 0.
     */
    error InvalidTokenPrice();

    /**
     * @dev Occurs when redeem or redeemBatch is called with an invalid recipient.
     */
    error InvalidRecipient();

    /**
     * @dev Occurs when the token address does not match the expected token address.
     */
    error TokenMismatch(address storedTokenAddress, address expectedTokenAddress);

    /**
     * @dev Occurs when an attempt is made to mint a token that is not mintable.
     */
    error TokenNotMintable();

    /**
     * @dev Occurs when the length of the two arrays do not match.
     */
    error ArrayLengthMismatch(uint256 lengthA, uint256 lengthB);

    /**
     * @dev Occurs when the price of an ERC20 Token is not the same as the expected price.
     */
    error ERC20TransferSlippage();

    /**
     * @dev Occurs when the address is not a redeem handler
     */
    error NotARedeemHandler(address handler);
}
