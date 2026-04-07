// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IERC165Upgradeable} from "@zoralabs/openzeppelin-contracts-upgradeable/contracts/interfaces/IERC165Upgradeable.sol";

/// @dev IERC165 type required
interface IRenderer1155 is IERC165Upgradeable {
    /// @notice Called for assigned tokenId, or when token id is globally set to a renderer
    /// @dev contract target is assumed to be msg.sender
    /// @param tokenId token id to get uri for
    function uri(uint256 tokenId) external view returns (string memory);

    /// @notice Only called for tokenId == 0
    /// @dev contract target is assumed to be msg.sender
    function contractURI() external view returns (string memory);

    /// @notice Sets up renderer from contract
    /// @param initData data to setup renderer with
    /// @dev contract target is assumed to be msg.sender
    function setup(bytes memory initData) external;

    // IERC165 type required – set in base helper
}
