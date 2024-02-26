// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

contract BoostedMinterFactoryStorageV1 {
    // tokenAddress => tokenId => minter
    mapping(address => mapping(uint256 => address)) public boostedMinterForCollection;
    uint256 private gap1;
}
