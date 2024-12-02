// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ISecondarySwap} from "../../src/interfaces/ISecondarySwap.sol";
import {Mock1155} from "./Mock1155.sol";
import {MockZoraTimedSale} from "./MockZoraTimedSale.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/interfaces/IERC1155Receiver.sol";

contract MockSecondarySwap is ISecondarySwap {
    MockZoraTimedSale immutable mockTimedSale;

    constructor(MockZoraTimedSale _mockTimedSale) {
        mockTimedSale = _mockTimedSale;
    }

    function buy1155(address erc20zAddress, uint256 num1155ToBuy, address payable recipient, address payable, uint256, uint160) external payable {
        (address collection, uint256 tokenId) = mockTimedSale.collectionForErc20z(erc20zAddress);
        if (collection == address(0)) revert("ERC20z not set");
        Mock1155(collection).mint(recipient, tokenId, num1155ToBuy, "");
    }

    function onERC1155Received(address, address, uint256 tokenId, uint256, bytes calldata) external view returns (bytes4) {
        address collection = msg.sender;
        address erc20zAddress = mockTimedSale.sale(collection, tokenId).erc20zAddress;
        if (erc20zAddress == address(0)) {
            revert SaleNotSet();
        }
        return IERC1155Receiver.onERC1155Received.selector;
    }
}
