// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Mock1155} from "./Mock1155.sol";
import {IZoraTimedSaleStrategy} from "../../src/interfaces/IZoraTimedSaleStrategy.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20z is ERC20 {
    constructor() ERC20("ERC20z", "ERC20z") {}
}

contract MockZoraTimedSale is IZoraTimedSaleStrategy {
    uint256 constant MINT_FEE = 0.000111 ether;

    function mint(address mintTo, uint256 quantity, address collection, uint256 tokenId, address, string calldata) external payable {
        if (msg.value != MINT_FEE * quantity) revert("Incorrect mint fee");
        Mock1155(collection).mint{value: msg.value}(mintTo, tokenId, quantity, "");
    }

    struct CollectionAndTokenId {
        address collection;
        uint256 tokenId;
    }

    mapping(address => mapping(uint256 => address)) internal saleStorage;
    mapping(address => CollectionAndTokenId) public collectionForErc20z;

    function setSale(address collection, uint256 tokenId) external returns (address erc20z) {
        erc20z = address(new MockERC20z());
        saleStorage[collection][tokenId] = erc20z;
        collectionForErc20z[erc20z] = CollectionAndTokenId(collection, tokenId);
    }

    function sale(address collection, uint256 tokenId) external view returns (SaleStorage memory _sale) {
        address erc20z = saleStorage[collection][tokenId];
        _sale.erc20zAddress = payable(erc20z);
    }
}
