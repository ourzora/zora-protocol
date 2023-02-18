// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IZoraCreator1155TypesV1} from "../nft/IZoraCreator1155TypesV1.sol";
import {IRenderer1155} from "../interfaces/IRenderer1155.sol";
import {IMinter1155} from "../interfaces/IMinter1155.sol";
import {ICreatorRoyaltiesControl} from "../interfaces/ICreatorRoyaltiesControl.sol";

interface IZoraCreator1155 is IZoraCreator1155TypesV1 {
    function PERMISSION_BIT_ADMIN() external returns (uint256);

    function PERMISSION_BIT_MINTER() external returns (uint256);

    function PERMISSION_BIT_SALES() external returns (uint256);

    function PERMISSION_BIT_METADATA() external returns (uint256);

    event UpdatedToken(address from, uint256 tokenId, TokenData tokenData);

    event ContractRendererUpdated(IRenderer1155 renderer);

    error UserMissingRoleForToken(address user, uint256 tokenId, uint256 role);

    error Mint_InsolventSaleTransfer();
    error Mint_ValueTransferFail();

    error Mint_TokenIDMintNotAllowed();

    error Mint_UnknownCommand();

    error NewOwnerNeedsToBeAdmin();

    error Sale_CallFailed();
    error Metadata_CallFailed();

    error ETHWithdrawFailed(address recipient, uint256 amount);
    error FundsWithdrawInsolvent(uint256 amount, uint256 contractValue);

    // TODO: maybe add more context
    error CannotMintMoreTokens(uint256 tokenId);

    function initialize(
        string memory contractURI,
        ICreatorRoyaltiesControl.RoyaltyConfiguration memory defaultRoyaltyConfiguration,
        address defaultAdmin,
        bytes[] calldata setupActions
    ) external;

    /// @notice Only allow minting one token id at time
    /// @dev Purchase contract function that calls the underlying sales function for commands
    /// @param minter Address for the minter
    /// @param tokenId tokenId to mint, set to 0 for new tokenId
    /// @param quantity to purchase
    /// @param minterArguments calldata for the minter contracts
    function purchase(
        IMinter1155 minter,
        uint256 tokenId,
        uint256 quantity,
        bytes calldata minterArguments
    ) external payable;

    function adminMint(
        address recipient,
        uint256 tokenId,
        uint256 quantity,
        bytes memory data
    ) external;

    function adminMintBatch(
        address recipient,
        uint256[] memory tokenIds,
        uint256[] memory quantities,
        bytes memory data
    ) external;

    /// @notice Contract call to setupNewToken
    /// @param _uri URI for the token
    /// @param maxSupply maxSupply for the token, set to 0 for open edition
    function setupNewToken(string memory _uri, uint256 maxSupply) external returns (uint256 tokenId);

    function setTokenMetadataRenderer(
        uint256 tokenId,
        IRenderer1155 renderer,
        bytes calldata setupData
    ) external;

    function contractURI() external view returns (string memory);

    function isAdminOrRole(
        address user,
        uint256 tokenId,
        uint256 role
    ) external view returns (bool);
}
