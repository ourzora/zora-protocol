// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface ICreatorRoyaltiesControl {
    struct RoyaltyConfiguration {
        uint32 royaltyMintSchedule;
        address royaltyRecipient;
    }

    event UpdatedRoyalties(uint256 tokenId, address user, RoyaltyConfiguration configuration);

    function getRoyalties(uint256 token) external view returns (RoyaltyConfiguration memory);
}
