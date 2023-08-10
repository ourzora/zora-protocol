// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {MathUpgradeable} from "@zoralabs/openzeppelin-contracts-upgradeable/contracts/utils/math/MathUpgradeable.sol";
import {ICreatorRoyaltiesControl} from "../interfaces/ICreatorRoyaltiesControl.sol";
import {IZoraCreator1155TypesV1} from "../nft/IZoraCreator1155TypesV1.sol";

library CreatorRoyaltiesCalc {
    uint256 constant CONTRACT_BASE_ID = 0;

    function calculateSupplyRoyalty(
        uint256 tokenId,
        uint256 mintAmount,
        mapping(uint256 => ICreatorRoyaltiesControl.RoyaltyConfiguration) storage royalties,
        mapping(uint256 => IZoraCreator1155TypesV1.TokenData) storage tokens
    ) external view returns (uint256 totalRoyaltyMints, address royaltyRecipient) {
        uint256 royaltyMintSchedule = royalties[tokenId].royaltyMintSchedule;
        if (royaltyMintSchedule == 0) {
            royaltyMintSchedule = royalties[CONTRACT_BASE_ID].royaltyMintSchedule;
        }
        if (royaltyMintSchedule == 0) {
            // If we still have no schedule, return 0 supply royalty.
            return (0, address(0));
        }
        uint256 maxSupply = tokens[tokenId].maxSupply;
        uint256 totalMinted = tokens[tokenId].totalMinted;

        totalRoyaltyMints = (mintAmount + (totalMinted % royaltyMintSchedule)) / (royaltyMintSchedule - 1);
        totalRoyaltyMints = MathUpgradeable.min(totalRoyaltyMints, maxSupply - (mintAmount + totalMinted));
        if (totalRoyaltyMints > 0) {
            royaltyRecipient = royalties[tokenId].royaltyRecipient;
            if (royaltyRecipient == address(0)) {
                royaltyRecipient = royalties[CONTRACT_BASE_ID].royaltyRecipient;
            }
            // If we have no recipient set, return 0 supply royalty.
            if (royaltyRecipient == address(0)) {
                totalRoyaltyMints = 0;
            }
        }
    }
}
