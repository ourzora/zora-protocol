// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {ICreatorRendererControl} from "../interfaces/ICreatorRendererControl.sol";
import {IRenderer1155} from "../interfaces/IRenderer1155.sol";

/// @notice Creator Renderer Storage Configuration Contract V1
abstract contract CreatorRendererStorageV1 is ICreatorRendererControl {
    struct CreatorRendererStorageV1Data {
        /// @notice Mapping for custom renderers
        mapping(uint256 => IRenderer1155) customRenderers;
    }

    function customRenderers(uint256 tokenId) public view returns (IRenderer1155) {
        return _get1155RendererStorage().customRenderers[tokenId];
    }

    function _get1155RendererStorage() internal pure returns (CreatorRendererStorageV1Data storage $) {
        assembly {
            $.slot := 301
        }
    }
}
