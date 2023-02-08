// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IZoraCreator1155TypesV1} from "../nft/IZoraCreator1155TypesV1.sol";
import {ICreatorRoyaltiesControl} from "../interfaces/ICreatorRoyaltiesControl.sol";

interface IZoraCreator1155 is IZoraCreator1155TypesV1 {
    function PERMISSION_BIT_ADMIN() external returns (uint256);

    function PERMISSION_BIT_MINTER() external returns (uint256);

    function PERMISSION_BIT_SALES() external returns (uint256);

    function PERMISSION_BIT_METADATA() external returns (uint256);

    event UpdatedToken(address from, uint256 tokenId, TokenData tokenData);

    error UserMissingRoleForToken(address user, uint256 tokenId, uint256 role);

    error ETHWithdrawFailed(address recipient, uint256 amount);
    error FundsWithdrawInsolvent(uint256 amount, uint256 contractValue);

    error OperatorNotAllowed(address operator, address from, address to);

    // TODO: maybe add more context
    error CannotMintMoreTokens(uint256 tokenId);

    function initialize(
        string memory contractURI,
        ICreatorRoyaltiesControl.RoyaltyConfiguration memory defaultRoyaltyConfiguration,
        address defaultAdmin,
        bytes[] calldata setupActions
    ) external;

    // Only allow minting one token id at time
    function purchase(
        address minter,
        uint256 tokenId,
        uint256 quantity,
        bytes calldata minterArguments
    ) external payable;

    function setupNewToken(string memory _uri, uint256 maxSupply) external returns (uint256 tokenId);

    event ContractURIUpdated(address updater, string newURI);

    event UpdatedMetadataRendererForToken(uint256 tokenId, address user, address metadataRenderer);
}
