// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IZoraCreator1155} from "../interfaces/IZoraCreator1155.sol";
import {PublicMulticall} from "../utils/PublicMulticall.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {ERC1155Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import {ZoraCreator1155StorageV1} from "./ZoraCreator1155StorageV1.sol";
import {IMinter1155} from "../interfaces/IMinter1155.sol";
import {CreatorPermissionControl} from "../permissions/CreatorPermissionControl.sol";

contract ZoraCreator1155Impl is
    IZoraCreator1155,
    ReentrancyGuardUpgradeable,
    PublicMulticall,
    ERC1155Upgradeable,
    ZoraCreator1155StorageV1,
    CreatorPermissionControl
{
    uint256 private immutable CONTRACT_BASE_ID = 0;

    uint256 public immutable PERMISSION_BIT_ADMIN = 1; // 0b1
    uint256 public immutable PERMISSION_BIT_MINTER = 2; // 0b01
    uint256 public immutable PERMISSION_BIT_SALES = 4; // 0b001
    uint256 public immutable PERMISSION_BIT_METADATA = 8; // 0b0001

    constructor() initializer {}

    function initialize(
        string memory contractURI,
        RoyaltyConfiguration memory defaultRoyaltyConfiguration,
        address defaultAdmin
    ) external initializer {
        // Initialize OZ 1155 implementation
        __ERC1155_init("");

        // Setup re-entracy guard
        __ReentrancyGuard_init();

        // Setup contract-default token ID
        _setupDefaultToken(
            defaultAdmin,
            contractURI,
            defaultRoyaltyConfiguration
        );
    }

    function _setupDefaultToken(
        address defaultAdmin,
        string memory contractURI,
        RoyaltyConfiguration memory defaultRoyaltyConfiguration
    ) internal {
        _addPermission(CONTRACT_BASE_ID, defaultAdmin, PERMISSION_BIT_ADMIN);

        // Mint token ID 0 / don't allow any user mints
        _setupNewToken(contractURI, 0);

        _updateRoyaltyConfiguration(
            CONTRACT_BASE_ID,
            defaultRoyaltyConfiguration
        );
    }

    // remove from OZ impl
    function _setURI(string memory newuri) internal virtual override {}

    function _getNextTokenId() internal returns (uint256) {
        unchecked {
            return ++nextTokenId;
        }
    }

    function _isAdminOrRole(
        address user,
        uint256 tokenId,
        uint256 role
    ) internal view returns (bool) {
        return _hasPermission(tokenId, user, PERMISSION_BIT_ADMIN | role);
    }

    function _requireAdminOrRole(
        address user,
        uint256 tokenId,
        uint256 role
    ) internal view {
        if (!_hasPermission(tokenId, user, PERMISSION_BIT_ADMIN | role)) {
            revert UserMissingRoleForToken(user, tokenId, role);
        }
    }

    modifier onlyAdminOrRole(uint256 tokenId, uint256 role) {
        _requireAdminOrRole(msg.sender, tokenId, role);
        _;
    }

    function requireCanMintQuantity(uint256 tokenId, uint256 quantity)
        internal
        view
    {
        TokenData memory tokenInformation = tokens[tokenId];
        if (
            tokenInformation.totalSupply + quantity >= tokens[tokenId].maxSupply
        ) {
            revert CannotMintMoreTokens(tokenId);
        }
    }

    modifier canMint(uint256 tokenId, uint256 quantity) {
        requireCanMintQuantity(tokenId, quantity);
        _;
    }

    function setupNewToken(string memory _uri, uint256 maxSupply)
        public
        onlyAdminOrRole(CONTRACT_BASE_ID, PERMISSION_BIT_MINTER)
        nonReentrant
        returns (uint256)
    {
        return _setupNewToken(_uri, maxSupply);
    }

    function _setupNewToken(string memory _uri, uint256 maxSupply)
        internal
        returns (uint256 tokenId)
    {
        tokenId = _getNextTokenId();
        TokenData memory tokenData = TokenData({
            uri: _uri,
            maxSupply: maxSupply,
            totalSupply: 0
        });
        tokens[tokenId] = tokenData;
        emit UpdatedToken(msg.sender, tokenId, tokenData);
    }

    function _updateRoyaltyConfiguration(
        uint256 tokenId,
        RoyaltyConfiguration memory royaltyConfiguration
    ) internal {
        royaltyConfigurations[tokenId] = royaltyConfiguration;

        emit RoyaltyConfigurationUpdated({
            tokenId: tokenId,
            sender: msg.sender,
            royaltyConfiguration: royaltyConfiguration
        });
    }

    function setTokenMetadataRenderer(
        uint256 tokenId,
        address metadataRenderer,
        bytes memory initData
    ) public {
        if (!_isAdminOrRole(msg.sender, tokenId, PERMISSION_BIT_METADATA)) {
            _requireAdminOrRole(msg.sender, tokenId, PERMISSION_BIT_METADATA);
        }

        metadataRendererContract[tokenId] = metadataRenderer;

        if (initData.length > 0) {
            // metadataRenderer.
        }

        emit UpdatedMetadataRendererForToken(
            tokenId,
            msg.sender,
            metadataRenderer
        );
    }

    function adminMint(
        address recipient,
        uint256 tokenId,
        uint256 quantity,
        bytes memory data
    ) public canMint(tokenId, quantity) nonReentrant {
        // First check token specific role
        if (!_isAdminOrRole(msg.sender, tokenId, PERMISSION_BIT_MINTER)) {
            // Then check admin role
            _requireAdminOrRole(
                msg.sender,
                CONTRACT_BASE_ID,
                PERMISSION_BIT_MINTER
            );
        }
        _mint(recipient, tokenId, quantity, data);
    }

    function adminMintBatch(
        address recipient,
        uint256[] memory tokenIds,
        uint256[] memory quantities,
        bytes memory data
    ) public nonReentrant {
        if (
            !_isAdminOrRole(msg.sender, CONTRACT_BASE_ID, PERMISSION_BIT_MINTER)
        ) {
            for (uint256 i = 0; i < tokenIds.length; ++i) {
                uint256 checkingTokenId = tokenIds[i];
                requireCanMintQuantity(tokenIds[i], quantities[i]);
                _requireAdminOrRole(
                    msg.sender,
                    checkingTokenId,
                    PERMISSION_BIT_MINTER
                );
            }
        }
        _mintBatch(recipient, tokenIds, quantities, data);
    }

    // multicall [
    //   mint() -- mint
    //   setSalesConfiguration() -- set sales configuration
    //   adminMint() -- mint reserved quantity
    // ]

    function executeCommands(Command[] calldata commands) internal {}

    // Only allow minting one token id at time
    function purchase(
        address minter,
        uint256 tokenId,
        uint256 quantity,
        address findersRecipient,
        bytes calldata minterArguments
    )
        external
        payable
        onlyAdminOrRole(tokenId, PERMISSION_BIT_MINTER)
        canMint(tokenId, quantity)
    {
        // executeCommands(
        IMinter1155(minter).requestMint(
            address(this),
            tokenId,
            quantity,
            findersRecipient,
            minterArguments
        );
        // );
    }
}
