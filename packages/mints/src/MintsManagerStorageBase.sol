// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {TokenConfig} from "./ZoraMintsTypes.sol";
import {IZoraMints1155} from "./interfaces/IZoraMints1155.sol";

abstract contract MintsManagerStorageBase {
    struct TransferredMints {
        address from;
        uint256[] tokenIds;
        uint256[] quantities;
    }

    /// @custom:storage-location erc7201:zora.storage.mints
    struct MintsManagerStorage {
        /// @notice Base MINTs contract address
        IZoraMints1155 mints;
        /// @notice Current mintable ETH token
        uint256 mintableEthToken;
        /// @notice mapping of erc20 token address to currently mintable erc20 token
        mapping(address => uint256) mintableERC20Token;
        /// @notice NFT Base URI (eg. ipfs://bafy.../) postpended with the token id (eg. ipfs://bafy.../3)
        string baseURI;
        /// @notice URI for the entire NFT contract as a JSON file. (eg. ipfs://bafy.../)
        string contractURI;
        /// @notice Transient variable to store transferred mints to be used in other calls
        TransferredMints transferredMints;
    }

    // keccak256(abi.encode(uint256(keccak256("zora.storage.mints-manager")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant MintsStorageLocation = 0x5e4926c1b2295beaf9fd187372d986e082174aa974602246c587bca3ef853900;

    function _getMintsManagerStorage() internal pure returns (MintsManagerStorage storage $) {
        assembly {
            $.slot := MintsStorageLocation
        }
    }
}
