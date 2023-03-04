// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

/// @title TransferHelperUtils
/// @notice Helper functions for sending ETH
library TransferHelperUtils {
    /// @dev Gas limit to send funds
    uint256 internal constant FUNDS_SEND_LOW_GAS_LIMIT = 110_000;

    // @dev Gas limit to send funds – usable for splits, can use with withdraws
    uint256 internal constant FUNDS_SEND_GAS_LIMIT = 310_000;

    /// @notice Sends ETH to a recipient, making conservative estimates to not run out of gas
    /// @param recipient The address to send ETH to
    /// @param value The amount of ETH to send
    function safeSendETHLowLimit(address recipient, uint256 value) internal returns (bool success) {
        (success, ) = recipient.call{value: value, gas: FUNDS_SEND_LOW_GAS_LIMIT}("");
    }

    /// @notice Sends ETH to a recipient, making an attempt to not run out of gas
    /// @param recipient The address to send ETH to
    /// @param value The amount of ETH to send
    function safeSendETH(address recipient, uint256 value) internal returns (bool success) {
        (success, ) = recipient.call{value: value, gas: FUNDS_SEND_GAS_LIMIT}("");
    }
}
