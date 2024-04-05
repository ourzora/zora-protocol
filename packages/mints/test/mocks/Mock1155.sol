// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IMinter1155, ICreatorCommands} from "@zoralabs/shared-contracts/interfaces/IMinter1155.sol";
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {IMintWithMints} from "../../src/IMintWithMints.sol";
import {IZoraMints1155} from "../../src/interfaces/IZoraMints1155.sol";
import {IZoraMintsMinterManager} from "../../src/interfaces/IZoraMintsMinterManager.sol";

contract Mock1155 is IMintWithMints, ERC1155 {
    IZoraMintsMinterManager private immutable mintsManager;

    constructor(IZoraMintsMinterManager _mints, address /* admin */, string memory /* uri */, string memory /* name */) ERC1155("") {
        mintsManager = _mints;
    }

    function transferMINTsToSelf(uint256[] calldata mintTokenIds, uint256[] calldata quantities) public {
        mintsManager.zoraMints1155().safeBatchTransferFrom(msg.sender, address(this), mintTokenIds, quantities, "");
    }

    function mintWithMints(
        uint256[] calldata mintTokenIds,
        uint256[] calldata quantities,
        IMinter1155,
        uint256,
        address[] memory,
        bytes calldata
    ) external payable override returns (uint256 quantityMinted) {
        transferMINTsToSelf(mintTokenIds, quantities);

        for (uint256 i = 0; i < mintTokenIds.length; i++) {
            quantityMinted += quantities[i];
        }
    }

    // /// Allows receiving ERC1155 tokens
    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC1155Receiver.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address operator,
        address from,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata data
    ) external pure returns (bytes4) {
        return IERC1155Receiver.onERC1155BatchReceived.selector;
    }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IMintWithMints).interfaceId || super.supportsInterface(interfaceId);
    }
}

contract MockMinter1155 is IMinter1155 {
    function requestMint(
        address sender,
        uint256 tokenId,
        uint256 quantity,
        uint256 ethValueSent,
        bytes calldata minterArguments
    ) external returns (ICreatorCommands.CommandSet memory commands) {}

    function supportsInterface(bytes4 interfaceId) external view override returns (bool) {
        return true;
    }
}
