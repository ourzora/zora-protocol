// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IMinter1155} from "@zoralabs/shared-contracts/interfaces/IMinter1155.sol";

/// @title IMintWithMints
/// @notice Interface intended to be implemented by a 1155 creator contract to be able to mint tokens using MINTs
interface IMintWithMints {
    /// @notice Mint tokens and payout rewards given a minter contract, minter arguments, and rewards arguments,
    /// while MINTs are redeemed to pay for the mint fee, instead of paying with ETH directly.
    /// The MINTs must have been transferred to be owned by this contract before calling this function.
    /// Value sent is used for paid mints, if this is a paid mint.
    /// @param mintTokenIds The MINT token IDs that are to be redeemed.
    /// @param quantities The quantities of each MINT token id to redeem.
    /// @param minter The minter contract to use
    /// @param tokenId The token ID to mint
    /// @param rewardsRecipients The addresses of rewards arguments - rewardsRecipients[0] = mintReferral, rewardsRecipients[1] = platformReferral
    /// @param minterArguments The arguments to pass to the minter
    /// @return quantityMinted The total quantity of tokens minted
    function mintWithMints(
        uint256[] calldata mintTokenIds,
        uint256[] calldata quantities,
        IMinter1155 minter,
        uint256 tokenId,
        address[] memory rewardsRecipients,
        bytes calldata minterArguments
    ) external payable returns (uint256 quantityMinted);
}
