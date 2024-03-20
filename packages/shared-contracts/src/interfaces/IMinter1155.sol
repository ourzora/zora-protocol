// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ICreatorCommands} from "./ICreatorCommands.sol";
import {IERC165Upgradeable} from "./IERC165Upgradeable.sol";

/// @notice Minter standard interface
/// @dev Minters need to confirm to the ERC165 selector of type(IMinter1155).interfaceId
interface IMinter1155 is IERC165Upgradeable {
    function requestMint(
        address sender,
        uint256 tokenId,
        uint256 quantity,
        uint256 ethValueSent,
        bytes calldata minterArguments
    ) external returns (ICreatorCommands.CommandSet memory commands);
}
