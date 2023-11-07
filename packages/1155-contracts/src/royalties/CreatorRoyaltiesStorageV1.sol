// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {ICreatorRoyaltiesControl} from "../interfaces/ICreatorRoyaltiesControl.sol";

/// Imagine. Mint. Enjoy.
/// @title CreatorRoyaltiesControl
/// @author ZORA @iainnash / @tbtstl
/// @notice Royalty storage contract pattern
abstract contract CreatorRoyaltiesStorageV1 is ICreatorRoyaltiesControl {
    struct CreatorRoyaltiesStorageV1Data {
        mapping(uint256 => RoyaltyConfiguration) royalties;
    }

    function _get1155CreatorRoyaltyV1() internal pure returns (CreatorRoyaltiesStorageV1Data storage $) {
        assembly {
            $.slot := 352 
        }
    }

    function royalties(uint256 tokenId) public view returns () {
       return _get1155CreatorRoyaltyV1().royalties[tokenId];
    }
}
