// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IZoraCreator1155TypesV1} from "./IZoraCreator1155TypesV1.sol";
import {IOwnable} from "../interfaces/IOwnable.sol";

contract ZoraCreator1155StorageV1 is IZoraCreator1155TypesV1, IOwnable {
    /// @notice token data stored for each token
    mapping(uint256 => TokenData) internal tokens;

    /// @notice metadata renderer contract for each token
    mapping(uint256 => address) public metadataRendererContract;

    /// @notice next token id available when using a linear mint style (default for launch)
    uint256 public nextTokenId;

    /// @notice Owner address proxy for 3rd party queries
    address public owner;

    /// @notice Default funds recipient address
    address public fundsRecipient;

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}
