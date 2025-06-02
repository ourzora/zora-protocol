// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @notice Interface for getting the correct message sender.
interface IMsgSender {
    /// @notice Returns the address of the message sender.
    /// @return The address of the message sender.
    function msgSender() external view returns (address);
}
