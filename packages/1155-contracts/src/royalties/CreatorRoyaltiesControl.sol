// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {CreatorRoyaltiesStorageV1} from "./CreatorRoyaltiesStorageV1.sol";
import {ICreatorRoyaltiesControl} from "../interfaces/ICreatorRoyaltiesControl.sol";
import {SharedBaseConstants} from "../shared/SharedBaseConstants.sol";
import {ICreatorRoyaltyErrors} from "../interfaces/ICreatorRoyaltiesControl.sol";
import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";

/// Imagine. Mint. Enjoy.
/// @title CreatorRoyaltiesControl
/// @author ZORA @iainnash / @tbtstl
/// @notice Contract for managing the royalties of an 1155 contract
abstract contract CreatorRoyaltiesControl is CreatorRoyaltiesStorageV1, SharedBaseConstants {
    uint256 immutable ROYALTY_BPS_TO_PERCENT = 10_000;

    /// @notice The royalty information for a given token.
    /// @param tokenId The token ID to get the royalty information for.
    function getRoyalties(uint256 tokenId) public view returns (RoyaltyConfiguration memory) {
        if (royalties[tokenId].royaltyRecipient != address(0)) {
            return royalties[tokenId];
        }
        // Otherwise, return default.
        return royalties[CONTRACT_BASE_ID];
    }

    /// @notice Returns the royalty information for a given token.
    /// @param tokenId The token ID to get the royalty information for.
    /// @param salePrice The sale price of the NFT asset specified by tokenId
    function royaltyInfo(uint256 tokenId, uint256 salePrice) public view returns (address receiver, uint256 royaltyAmount) {
        RoyaltyConfiguration memory config = getRoyalties(tokenId);
        royaltyAmount = (config.royaltyBPS * salePrice) / ROYALTY_BPS_TO_PERCENT;
        receiver = config.royaltyRecipient;
    }

    function _updateRoyalties(uint256 tokenId, RoyaltyConfiguration memory configuration) internal {
        // If a nonzero royalty mint schedule is set:
        if (configuration.royaltyMintSchedule != 0) {
            // Set the value to zero
            configuration.royaltyMintSchedule = 0;
        }
        // Don't allow setting royalties to burn address
        if (configuration.royaltyRecipient == address(0) && configuration.royaltyBPS > 0) {
            revert ICreatorRoyaltyErrors.InvalidMintSchedule();
        }
        royalties[tokenId] = configuration;

        emit UpdatedRoyalties(tokenId, msg.sender, configuration);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual returns (bool) {
        return interfaceId == type(IERC2981).interfaceId;
    }
}
