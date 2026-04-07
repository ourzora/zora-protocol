// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {ICreatorRendererControl} from "../interfaces/ICreatorRendererControl.sol";
import {IRenderer1155} from "../interfaces/IRenderer1155.sol";

/// @notice Creator Renderer Storage Configuration Contract V1
abstract contract CreatorRendererStorageV1 is ICreatorRendererControl {
    /// @notice Mapping for custom renderers
    mapping(uint256 => IRenderer1155) public customRenderers;

    uint256[50] private __gap;
}
