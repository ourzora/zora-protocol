// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IMinter1155} from "./IMinter1155.sol";

interface IMintWithRewardsRecipients {
    /// @notice Mint tokens and payout rewards given a minter contract, minter arguments, and rewards arguments
    /// @param minter The minter contract to use
    /// @param tokenId The token ID to mint
    /// @param quantity The quantity of tokens to mint
    /// @param rewardsRecipients The addresses of rewards arguments - mintReferral and platformReferral
    /// @param minterArguments The arguments to pass to the minter
    function mint(IMinter1155 minter, uint256 tokenId, uint256 quantity, address[] memory rewardsRecipients, bytes calldata minterArguments) external payable;
}
