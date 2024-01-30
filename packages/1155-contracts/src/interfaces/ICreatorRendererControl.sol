// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IRenderer1155} from "./IRenderer1155.sol";

/// @notice Interface for creator renderer controls
interface ICreatorRendererControl {
    /// @notice Get the custom renderer contract (if any) for the given token id
    /// @dev Reverts if not custom renderer is set for this token
    function getCustomRenderer(uint256 tokenId) external view returns (IRenderer1155 renderer);

    error NoRendererForToken(uint256 tokenId);
    error RendererNotValid(address renderer);
    event RendererUpdated(uint256 indexed tokenId, address indexed renderer, address indexed user);
}
