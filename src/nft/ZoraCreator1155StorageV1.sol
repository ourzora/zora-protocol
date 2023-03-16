// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IZoraCreator1155TypesV1} from "./IZoraCreator1155TypesV1.sol";
import {IOwnable} from "../interfaces/IOwnable.sol";

contract ZoraCreator1155StorageV1 is IZoraCreator1155TypesV1, IOwnable {
    mapping(uint256 => TokenData) public tokens;

    mapping(uint256 => address) public metadataRendererContract;

    uint256 public nextTokenId;

    /// @notice Owner address proxy for 3rd party queries
    address public owner;

    /// @notice Global contract configuration
    ContractConfig config;

    uint256[50] private __gap;
}
