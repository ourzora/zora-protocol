// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/**
 * @dev Interface of the ERC165 standard, as defined in the
 * https://eips.ethereum.org/EIPS/eip-165[EIP].
 *
 * Implementers can declare support of contract interfaces, which can then be
 * queried by others ({ERC165Checker}).
 *
 * For an implementation, see {ERC165}.
 */
interface IERC165 {
    /**
     * @dev Returns true if this contract implements the interface defined by
     * `interfaceId`. See the corresponding
     * https://eips.ethereum.org/EIPS/eip-165#how-interfaces-are-identified[EIP section]
     * to learn more about how these ids are created.
     *
     * This function call must use less than 30 000 gas.
     */
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

/**
 * @dev Interface for the NFT Royalty Standard.
 *
 * A standardized way to retrieve royalty payment information for non-fungible tokens (NFTs) to enable universal
 * support for royalty payments across all NFT marketplaces and ecosystem participants.
 *
 * _Available since v4.5._
 */
interface IERC2981 is IERC165 {
    /**
     * @dev Returns how much royalty is owed and to whom, based on a sale price that may be denominated in any unit of
     * exchange. The royalty amount is denominated and should be paid in that same unit of exchange.
     */
    function royaltyInfo(uint256 tokenId, uint256 salePrice) external view returns (address receiver, uint256 royaltyAmount);
}

interface ICreatorRoyaltyErrors {
    /// @notice Thrown when a user tries to have 100% supply royalties
    error InvalidMintSchedule();
}

interface ICreatorRoyaltiesControl is IERC2981 {
    /// @notice The RoyaltyConfiguration struct is used to store the royalty configuration for a given token.
    /// @param royaltyMintSchedule Every nth token will go to the royalty recipient.
    /// @param royaltyBPS The royalty amount in basis points for secondary sales.
    /// @param royaltyRecipient The address that will receive the royalty payments.
    struct RoyaltyConfiguration {
        uint32 royaltyMintSchedule;
        uint32 royaltyBPS;
        address royaltyRecipient;
    }

    /// @notice Event emitted when royalties are updated
    event UpdatedRoyalties(uint256 indexed tokenId, address indexed user, RoyaltyConfiguration configuration);

    /// @notice External data getter to get royalties for a token
    /// @param tokenId tokenId to get royalties configuration for
    function getRoyalties(uint256 tokenId) external view returns (RoyaltyConfiguration memory);
}
