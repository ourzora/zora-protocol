// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {CreatorRendererStorageV1} from "./CreatorRendererStorageV1.sol";
import {IRenderer1155} from "../interfaces/IRenderer1155.sol";

abstract contract CreatorRendererControl is CreatorRendererStorageV1 {
    function _setRenderer(
        uint256 tokenId,
        IRenderer1155 renderer,
        bytes calldata setupData
    ) internal {
        customRenderers[tokenId] = renderer;
        if (!renderer.supportsInterface(type(IRenderer1155).interfaceId)) {
            revert RendererNotValid(address(renderer));
        }
        renderer.setup(setupData);

        emit RendererUpdated({tokenId: tokenId, renderer: address(renderer), user: msg.sender});
    }

    function getCustomRenderer(uint256 tokenId) public view returns (IRenderer1155 renderer) {
        renderer = customRenderers[tokenId];
        if (address(renderer) == address(0)) {
            revert NoRendererForToken(tokenId);
        }
    }

    function _render(uint256 tokenId) internal view returns (string memory) {
        return getCustomRenderer(tokenId).uriFromContract(address(this), tokenId);
    }
}
