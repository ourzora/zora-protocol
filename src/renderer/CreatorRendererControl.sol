// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {CreatorRendererStorageV1} from "./CreatorRendererStorageV1.sol";
import {IRenderer1155} from "../interfaces/IRenderer1155.sol";
import {ITransferHookReceiver} from "../interfaces/ITransferHookReceiver.sol";
import {SharedBaseConstants} from "../shared/SharedBaseConstants.sol";

/// @title CreatorRendererControl
/// @notice Contract for managing the renderer of an 1155 contract
abstract contract CreatorRendererControl is CreatorRendererStorageV1, SharedBaseConstants {
    function _setRenderer(uint256 tokenId, IRenderer1155 renderer) internal {
        customRenderers[tokenId] = renderer;
        if (address(renderer) != address(0)) {
            if (!renderer.supportsInterface(type(IRenderer1155).interfaceId)) {
                revert RendererNotValid(address(renderer));
            }
        }

        emit RendererUpdated({tokenId: tokenId, renderer: address(renderer), user: msg.sender});
    }

    /// @notice Return the renderer for a given token
    /// @dev Returns address 0 for no results
    /// @param tokenId The token to get the renderer for
    function getCustomRenderer(uint256 tokenId) public view returns (IRenderer1155 customRenderer) {
        customRenderer = customRenderers[tokenId];
        if (address(customRenderer) == address(0)) {
            customRenderer = customRenderers[CONTRACT_BASE_ID];
        }
    }

    /// @notice Function called to render when an empty tokenURI exists on the contract
    function _render(uint256 tokenId) internal view returns (string memory) {
        return getCustomRenderer(tokenId).uri(tokenId);
    }
}
