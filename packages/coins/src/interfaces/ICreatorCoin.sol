// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ICoin} from "./ICoin.sol";

interface ICreatorCoin is ICoin {
    /// @notice Emitted when creator vesting tokens are claimed
    /// @param recipient The address that received the vested tokens
    /// @param claimAmount The amount of tokens claimed in this transaction
    /// @param totalClaimed The total amount of tokens claimed so far
    /// @param vestingStartTime The timestamp when vesting started
    /// @param vestingEndTime The timestamp when vesting ends
    event CreatorVestingClaimed(address indexed recipient, uint256 claimAmount, uint256 totalClaimed, uint256 vestingStartTime, uint256 vestingEndTime);

    /// @notice Thrown when an invalid currency is used for creator coin operations
    error InvalidCurrency();

    /// @notice Allows the creator payout recipient to claim vested tokens
    /// @return claimAmount The amount of tokens claimed
    function claimVesting() external returns (uint256);

    /// @notice Get the amount of vested tokens that can be claimed
    /// @return claimAmount The amount of tokens that can be claimed
    function getClaimableAmount() external view returns (uint256);
}
