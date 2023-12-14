// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IZoraAccountFactory {
    /// @notice Emitted when a Zora Account Factory is first initialized
    /// @param owner The initial owner
    /// @param sender The sender of the transaction
    event ZoraAccountFactoryInitialized(address indexed owner, address indexed sender);
}
