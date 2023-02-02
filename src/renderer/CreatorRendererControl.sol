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

        emit RendererUpdated({
            tokenId: tokenId,
            renderer: address(renderer),
            user: msg.sender
        });
    }

    function hasRenderer(uint256 tokenId) public returns (bool) {
        return address(customRenderers[tokenId]) != address(0);
    }

    function _render(uint256 tokenId) internal returns (string memory) {
      return customRenderers[tokenId].uriFromContract(address(this), tokenId);
    }
}
