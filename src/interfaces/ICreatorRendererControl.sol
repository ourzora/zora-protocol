// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IRenderer1155} from "./IRenderer1155.sol";

interface ICreatorRendererControl {
    function getCustomRenderer(uint256 tokenId) external view returns (IRenderer1155);

    error NoRendererForToken(uint256 tokenId);
    error RendererNotValid(address renderer);
    event RendererUpdated(uint256 tokenId, address renderer, address user);
}
