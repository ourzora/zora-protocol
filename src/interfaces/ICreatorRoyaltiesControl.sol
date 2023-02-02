// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";

interface ICreatorRoyaltiesControl is IERC2981 {
    struct RoyaltyConfiguration {
        uint32 royaltyBPS;
        address royaltyRecipient;
    }

    event UpdatedRoyalties(
        uint256 tokenId,
        address user,
        RoyaltyConfiguration configuration
    );

    function getRoyalties(uint256 token)
        external
        view
        returns (RoyaltyConfiguration memory);
}
