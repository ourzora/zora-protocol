// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {CreatorRoyaltiesStorageV1} from "./CreatorRoyaltiesStorageV1.sol";
import {ICreatorRoyaltiesControl} from "../interfaces/ICreatorRoyaltiesControl.sol";
import {SharedBaseConstants} from "../shared/SharedBaseConstants.sol";

abstract contract CreatorRoyaltiesControl is CreatorRoyaltiesStorageV1, SharedBaseConstants {
    function getRoyalties(uint256 tokenId) public view returns (RoyaltyConfiguration memory) {
        RoyaltyConfiguration memory config = royalties[tokenId];
        if (config.royaltyRecipient != address(0)) {
            return config;
        }
        // Otherwise, return default.
        return royalties[CONTRACT_BASE_ID];
    }

    /// @notice Returns the royalty information for a given token.
    /// @param tokenId The token ID to get the royalty information for.
    /// @param mintAmount The amount of tokens being minted.
    /// @param totalSupply The total supply of the token,
    function royaltyInfo(uint256 tokenId, uint256 totalSupply, uint256 mintAmount) public view returns (address receiver, uint256 royaltyAmount) {
        RoyaltyConfiguration memory config = getRoyalties(tokenId);
        uint256 existingRoyaltySupply = totalSupply / config.royaltyMintSchedule;
        uint256 postMintRoyaltySupply = (totalSupply + mintAmount) / config.royaltyMintSchedule;
        return (config.royaltyRecipient, postMintRoyaltySupply - existingRoyaltySupply);
    }

    function _updateRoyalties(uint256 tokenId, RoyaltyConfiguration memory configuration) internal {
        royalties[tokenId] = configuration;
        emit UpdatedRoyalties(tokenId, msg.sender, configuration);
    }
}
