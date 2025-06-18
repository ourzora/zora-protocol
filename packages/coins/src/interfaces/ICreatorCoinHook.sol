// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface ICreatorCoinHook {
    /// @notice Emitted when creator coin rewards are distributed
    /// @param coin The address of the creator coin associated with rewards
    /// @param currency The address of the currency in which rewards are paid
    /// @param creator The address of the creator receiving rewards
    /// @param protocol The address of the protocol receiving rewards
    /// @param creatorAmount The amount of `currency` distributed to the creator
    /// @param protocolAmount The amount of `currency` distributed to the protocol
    event CreatorCoinRewards(address indexed coin, address currency, address creator, address protocol, uint256 creatorAmount, uint256 protocolAmount);
}
