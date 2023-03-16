// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IZoraCreator1155TypesV1} from "./IZoraCreator1155TypesV1.sol";

contract ZoraCreator1155StorageV1 is IZoraCreator1155TypesV1 {
    mapping(uint256 => TokenData) public tokens;

    mapping(uint256 => address) public metadataRendererContract;

    uint256 public nextTokenId;

    /// @notice Global contract configuration
    ContractConfig config;

    uint256[50] private __gap;
}
