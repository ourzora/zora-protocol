// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {TokenConfig} from "./ZoraSparksTypes.sol";
import {IZoraSparks1155} from "./interfaces/IZoraSparks1155.sol";

abstract contract SparksManagerStorageBase {
    struct TransferredSparks {
        address from;
        uint256[] tokenIds;
        uint256[] quantities;
    }

    /// @custom:storage-location erc7201:zora.storage.sparks
    struct SparksManagerStorage {
        /// @notice Base SPARKs contract address
        IZoraSparks1155 sparks;
        /// @notice NFT Base URI (eg. ipfs://bafy.../) postpended with the token id (eg. ipfs://bafy.../3)
        string baseURI;
        /// @notice URI for the entire NFT contract as a JSON file. (eg. ipfs://bafy.../)
        string contractURI;
        /// @notice Transient variable to store transferred sparks to be used in other calls
        TransferredSparks transferredSparks;
    }

    // keccak256(abi.encode(uint256(keccak256("zora.storage.sparks-manager")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant SparksStorageLocation = 0x5e4926c1b2295beaf9fd187372d986e082174aa974602246c587bca3ef853900;

    function _getSparksManagerStorage() internal pure returns (SparksManagerStorage storage $) {
        assembly {
            $.slot := SparksStorageLocation
        }
    }
}
