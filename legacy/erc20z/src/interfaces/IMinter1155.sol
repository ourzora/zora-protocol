// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ICreatorCommands} from "./ICreatorCommands.sol";

interface IMinter1155 {
    function supportsInterface(bytes4 interfaceId) external view returns (bool);

    function requestMint(
        address sender,
        uint256 tokenId,
        uint256 quantity,
        uint256 ethValueSent,
        bytes calldata minterArguments
    ) external returns (ICreatorCommands.CommandSet memory commands);
}
