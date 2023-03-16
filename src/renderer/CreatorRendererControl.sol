// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {CreatorRendererStorageV1} from "./CreatorRendererStorageV1.sol";
import {IRenderer1155} from "../interfaces/IRenderer1155.sol";

/// @title CreatorRendererControl
/// @notice Contract for managing the renderer of an 1155 contract
abstract contract CreatorRendererControl is CreatorRendererStorageV1 {
    function _setRenderer(uint256 tokenId, IRenderer1155 renderer, bytes calldata setupData) internal {
        customRenderers[tokenId] = renderer;
        if (!renderer.supportsInterface(type(IRenderer1155).interfaceId)) {
            revert RendererNotValid(address(renderer));
        }
        renderer.setup(setupData);

        emit RendererUpdated({tokenId: tokenId, renderer: address(renderer), user: msg.sender});
    }

    /// @notice Return the renderer for a given token
    /// @param tokenId The token to get the renderer for
    function getCustomRenderer(uint256 tokenId) public view returns (IRenderer1155 renderer) {
        renderer = customRenderers[tokenId];
        if (address(renderer) == address(0)) {
            revert NoRendererForToken(tokenId);
        }
    }

    /// @notice Function called to render when an empty tokenURI exists on the contract
    function _render(uint256 tokenId) internal view returns (string memory) {
        return getCustomRenderer(tokenId).uriFromContract(address(this), tokenId);
    }
}
