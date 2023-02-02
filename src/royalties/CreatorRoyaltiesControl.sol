// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {CreatorRoyaltiesStorageV1} from "./CreatorRoyaltiesStorageV1.sol";
import {ICreatorRoyaltiesControl} from "../interfaces/ICreatorRoyaltiesControl.sol";
import {SharedBaseConstants} from "../shared/SharedBaseConstants.sol";
import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";

abstract contract CreatorRoyaltiesControl is
    CreatorRoyaltiesStorageV1,
    SharedBaseConstants
{
    uint256 immutable ROYALTY_BPS_TO_PERCENT = 10_000;

    function getRoyalties(uint256 tokenId)
        public
        view
        returns (RoyaltyConfiguration memory)
    {
        RoyaltyConfiguration memory config = royalties[tokenId];
        if (config.royaltyBPS == 0) {
            return config;
        }
        // Otherwise, return default.
        return royalties[CONTRACT_BASE_ID];
    }

    function royaltyInfo(uint256 tokenId, uint256 salePrice)
        external
        view
        returns (address receiver, uint256 royaltyAmount)
    {
        RoyaltyConfiguration memory config = getRoyalties(tokenId);
        royaltyAmount =
            (config.royaltyBPS * salePrice) /
            ROYALTY_BPS_TO_PERCENT;
        receiver = config.royaltyRecipient;
    }

    function _updateRoyalties(
        uint256 tokenId,
        RoyaltyConfiguration memory configuration
    ) internal {
        royalties[tokenId] = configuration;
        emit UpdatedRoyalties(tokenId, msg.sender, configuration);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        returns (bool)
    {
        return interfaceId == type(IERC2981).interfaceId;
    }
}
