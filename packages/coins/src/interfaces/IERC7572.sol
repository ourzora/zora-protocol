// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @notice For compatibility with ERC7572 - the interface for contract-level metadata
/// @dev https://eips.ethereum.org/EIPS/eip-7572
interface IERC7572 {
    /// @notice Emitted when the contract URI is updated
    event ContractURIUpdated();

    /// @notice Returns the contract-level metadata
    function contractURI() external view returns (string memory);
}
