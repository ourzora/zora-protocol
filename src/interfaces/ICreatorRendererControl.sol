// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface ICreatorRendererControl {
    function getCustomRenderer(uint256 token) external view returns (address);

    error RendererNotValid(address renderer);
    event RendererUpdated(uint256 tokenId, address renderer, address user);
}
