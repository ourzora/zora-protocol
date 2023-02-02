// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IZoraCreator1155TypesV1} from "../nft/IZoraCreator1155TypesV1.sol";

interface IZoraCreator1155 is IZoraCreator1155TypesV1 {
    function PERMISSION_BIT_ADMIN() external returns (uint256);

    function PERMISSION_BIT_MINTER() external returns (uint256);

    function PERMISSION_BIT_SALES() external returns (uint256);

    function PERMISSION_BIT_METADATA() external returns (uint256);

    event UpdatedToken(address from, uint256 tokenId, TokenData tokenData);

    error UserMissingRoleForToken(address user, uint256 tokenId, uint256 role);

    event RoyaltyConfigurationUpdated(
        uint256 tokenId,
        address sender,
        RoyaltyConfiguration royaltyConfiguration
    );

    // TODO: maybe add more context
    error CannotMintMoreTokens(uint256 tokenId);

    // Only allow minting one token id at time
    function purchase(
        address minter,
        uint256 tokenId,
        uint256 quantity,
        address findersRecipient,
        bytes calldata minterArguments
    ) external payable;

    function setupNewToken(string memory _uri, uint256 maxSupply)
        external
        returns (uint256 tokenId);

    event ContractURIUpdated(address updater, string newURI);

    event UpdatedMetadataRendererForToken(
        uint256 tokenId,
        address user,
        address metadataRenderer
    );
}
