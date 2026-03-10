// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @title ITrendCoinErrors
/// @notice Shared error interface for TrendCoin-related errors
/// @dev Used by both TrendCoin and ZoraFactoryImpl for consistent error handling
interface ITrendCoinErrors {
    /// @notice Thrown when ticker symbol contains invalid characters

    /// @dev Allowed characters: 0-9, A-Z, a-z
    error TickerInvalidCharacters();

    /// @dev Ticker min length is 2
    error TickerTooShort();
    /// @dev Ticker max length is 32
    error TickerTooLong();

    /// @notice Thrown when attempting to deploy a trend coin with a ticker that already exists
    /// @param symbol The ticker symbol that was already used
    error TickerAlreadyUsed(string symbol);

    /// @notice Thrown when attempting to use the legacy initialize function for a trend coin
    error UseSpecificTrendCoinInitialize();
}
