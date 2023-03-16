// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IERC1155MetadataURIUpgradeable} from "@openzeppelin/contracts-upgradeable/interfaces/IERC1155MetadataURIUpgradeable.sol";
import {IZoraCreator1155TypesV1} from "../nft/IZoraCreator1155TypesV1.sol";
import {IRenderer1155} from "../interfaces/IRenderer1155.sol";
import {IMinter1155} from "../interfaces/IMinter1155.sol";
import {IVersionedContract} from "./IVersionedContract.sol";
import {ICreatorRoyaltiesControl} from "../interfaces/ICreatorRoyaltiesControl.sol";

/// @notice Main interface for the ZoraCreator1155 contract
interface IZoraCreator1155 is IZoraCreator1155TypesV1, IVersionedContract, IERC1155MetadataURIUpgradeable {
    function PERMISSION_BIT_ADMIN() external returns (uint256);

    function PERMISSION_BIT_MINTER() external returns (uint256);

    function PERMISSION_BIT_SALES() external returns (uint256);

    function PERMISSION_BIT_METADATA() external returns (uint256);

    event UpdatedToken(address indexed from, uint256 indexed tokenId, TokenData tokenData);
    event SetupNewToken(uint256 indexed tokenId, address indexed sender, string _uri, uint256 maxSupply);

    function setOwner(address newOwner) external;

    event ContractRendererUpdated(IRenderer1155 renderer);
    event ContractMetadataUpdated(address indexed updater, string uri, string name);
    event Purchased(address indexed sender, address indexed minter, uint256 indexed tokenId, uint256 quantity, uint256 value);

    error TokenIdMismatch(uint256 expected, uint256 actual);
    error NotAllowedContractBaseIDUpdate();
    error UserMissingRoleForToken(address user, uint256 tokenId, uint256 role);

    error Mint_InsolventSaleTransfer();
    error Mint_ValueTransferFail();
    error Mint_TokenIDMintNotAllowed();
    error Mint_UnknownCommand();

    error Burn_NotOwnerOrApproved(address operator, address user);

    error NewOwnerNeedsToBeAdmin();

    error Sale_CallFailed();

    error Renderer_CallFailed(bytes reason);
    error Renderer_NotValidRendererContract();

    error ETHWithdrawFailed(address recipient, uint256 amount);
    error FundsWithdrawInsolvent(uint256 amount, uint256 contractValue);

    error CannotMintMoreTokens(uint256 tokenId, uint256 quantity, uint256 totalMinted, uint256 maxSupply);

    function initialize(
        string memory contractURI,
        ICreatorRoyaltiesControl.RoyaltyConfiguration memory defaultRoyaltyConfiguration,
        address defaultAdmin,
        bytes[] calldata setupActions
    ) external;

    /// @notice Only allow minting one token id at time
    /// @dev Mint contract function that calls the underlying sales function for commands
    /// @param minter Address for the minter
    /// @param tokenId tokenId to mint, set to 0 for new tokenId
    /// @param quantity to mint
    /// @param minterArguments calldata for the minter contracts
    function mint(
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

    function burn(
        address user,
        uint256 tokenId,
        uint256 amount
    ) external;

    function burnBatch(
        address user,
        uint256[] calldata tokenIds,
        uint256[] calldata amounts
    ) external;

    /// @notice Contract call to setupNewToken
    /// @param _uri URI for the token
    /// @param maxSupply maxSupply for the token, set to 0 for open edition
    function setupNewToken(string memory _uri, uint256 maxSupply) external returns (uint256 tokenId);

    function updateTokenURI(uint256 tokenId, string memory _newURI) external;

    function updateContractMetadata(string memory _newURI, string memory _newName) external;

    function setTokenMetadataRenderer(
        uint256 tokenId,
        IRenderer1155 renderer,
        bytes calldata setupData
    ) external;

    function contractURI() external view returns (string memory);

    function assumeLastTokenIdMatches(uint256 tokenId) external;

    function updateRoyaltiesForToken(uint256 tokenId, ICreatorRoyaltiesControl.RoyaltyConfiguration memory royaltyConfiguration) external;

    function addPermission(
        uint256 tokenId,
        address user,
        uint256 permissionBits
    ) external;

    function removePermission(
        uint256 tokenId,
        address user,
        uint256 permissionBits
    ) external;

    function isAdminOrRole(
        address user,
        uint256 tokenId,
        uint256 role
    ) external view returns (bool);

    function getTokenInfo(uint256 tokenId) external view returns (TokenData memory);

    function callRenderer(uint256 tokenId, bytes memory data) external;

    function callSale(
        uint256 tokenId,
        IMinter1155 salesConfig,
        bytes memory data
    ) external;
}
