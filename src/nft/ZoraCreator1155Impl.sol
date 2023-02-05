// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IZoraCreator1155} from "../interfaces/IZoraCreator1155.sol";
import {PublicMulticall} from "../utils/PublicMulticall.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {ERC1155Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import {ZoraCreator1155StorageV1} from "./ZoraCreator1155StorageV1.sol";
import {IMinter1155} from "../interfaces/IMinter1155.sol";
import {IZoraCreator1155Factory} from "../interfaces/IZoraCreator1155Factory.sol";
import {CreatorPermissionControl} from "../permissions/CreatorPermissionControl.sol";
import {CreatorRoyaltiesControl} from "../royalties/CreatorRoyaltiesControl.sol";
import {SharedBaseConstants} from "../shared/SharedBaseConstants.sol";
import {TransferHelperUtils} from "../utils/TransferHelperUtils.sol";
import {MintFeeManager} from "../fee/MintFeeManager.sol";

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract ZoraCreator1155Impl is
    IZoraCreator1155,
    ReentrancyGuardUpgradeable,
    PublicMulticall,
    ERC1155Upgradeable,
    MintFeeManager,
    UUPSUpgradeable,
    ZoraCreator1155StorageV1,
    CreatorPermissionControl,
    CreatorRoyaltiesControl
{
    uint256 public immutable PERMISSION_BIT_ADMIN = 2 ** 1;
    uint256 public immutable PERMISSION_BIT_MINTER = 2 ** 2;
    uint256 public immutable PERMISSION_BIT_SALES = 2 ** 3;
    uint256 public immutable PERMISSION_BIT_METADATA = 2 ** 4;
    uint256 public immutable PERMISSION_BIT_FUNDS_MANAGER = 2 ** 5;

    IZoraCreator1155Factory public immutable factory;

    constructor(IZoraCreator1155Factory _factory, uint256 _mintFeeBPS, address _mintFeeRecipient) MintFeeManager(_mintFeeBPS, _mintFeeRecipient) initializer {
        factory = _factory;
    }

    function initialize(
        string memory contractURI,
        RoyaltyConfiguration memory defaultRoyaltyConfiguration,
        address defaultAdmin,
        bytes[] calldata setupActions
    ) external initializer {
        // Initialize OZ 1155 implementation
        __ERC1155_init(contractURI);

        // Setup re-entracy guard
        __ReentrancyGuard_init();

        // Setup contract-default token ID
        _setupDefaultToken(defaultAdmin, contractURI, defaultRoyaltyConfiguration);

        // Run Setup actions
        if (setupActions.length > 0) {
            // Temporarily make sender admin
            _addPermission(CONTRACT_BASE_ID, msg.sender, PERMISSION_BIT_ADMIN);

            // Make calls
            multicall(setupActions);

            // Remove admin
            _addPermission(CONTRACT_BASE_ID, msg.sender, PERMISSION_BIT_ADMIN);
            _removePermission(CONTRACT_BASE_ID, msg.sender, PERMISSION_BIT_ADMIN);
        }
    }

    function _setupDefaultToken(address defaultAdmin, string memory contractURI, RoyaltyConfiguration memory defaultRoyaltyConfiguration) internal {
        // Add admin permission to default admin to manage contract
        _addPermission(CONTRACT_BASE_ID, defaultAdmin, PERMISSION_BIT_ADMIN);

        // Mint token ID 0 / don't allow any user mints
        _setupNewToken(contractURI, 0);

        // Update default royalties
        _updateRoyalties(CONTRACT_BASE_ID, defaultRoyaltyConfiguration);
    }

    // remove from openzeppelin impl
    function _setURI(string memory newuri) internal virtual override {}

    function _getNextTokenId() internal returns (uint256) {
        unchecked {
            return nextTokenId++;
        }
    }

    function _isAdminOrRole(address user, uint256 tokenId, uint256 role) internal view returns (bool) {
        return _hasPermission(tokenId, user, PERMISSION_BIT_ADMIN | role);
    }

    function _requireAdminOrRole(address user, uint256 tokenId, uint256 role) internal view {
        if (!_hasPermission(tokenId, user, PERMISSION_BIT_ADMIN | role)) {
            revert UserMissingRoleForToken(user, tokenId, role);
        }
    }

    function _requireAdmin(address user, uint256 tokenId) internal view {
        _hasPermission(tokenId, user, PERMISSION_BIT_ADMIN);
    }

    modifier onlyAdminOrRole(uint256 tokenId, uint256 role) {
        _requireAdminOrRole(msg.sender, tokenId, role);
        _;
    }

    modifier onlyAdmin(uint256 tokenId) {
        _requireAdmin(msg.sender, tokenId);
        _;
    }

    function requireCanMintQuantity(uint256 tokenId, uint256 quantity) internal view {
        TokenData memory tokenInformation = tokens[tokenId];
        if (tokenInformation.totalSupply + quantity > tokenInformation.maxSupply) {
            revert CannotMintMoreTokens(tokenId);
        }
    }

    modifier canMint(uint256 tokenId, uint256 quantity) {
        requireCanMintQuantity(tokenId, quantity);
        _;
    }

    function setupNewToken(
        string memory _uri,
        uint256 maxSupply
    ) public onlyAdminOrRole(CONTRACT_BASE_ID, PERMISSION_BIT_MINTER) nonReentrant returns (uint256) {
        uint256 tokenId = _setupNewToken(_uri, maxSupply);
        // Allow the token creator to administrate this token
        _addPermission(tokenId, msg.sender, PERMISSION_BIT_ADMIN);
        return tokenId;
    }

    function _setupNewToken(string memory _uri, uint256 maxSupply) internal returns (uint256 tokenId) {
        tokenId = _getNextTokenId();
        TokenData memory tokenData = TokenData({uri: _uri, maxSupply: maxSupply, totalSupply: 0});
        tokens[tokenId] = tokenData;
        emit UpdatedToken(msg.sender, tokenId, tokenData);
    }

    function setTokenMetadataRenderer(
        uint256 tokenId,
        address metadataRenderer,
        bytes memory initData
    ) public onlyAdminOrRole(tokenId, PERMISSION_BIT_METADATA) nonReentrant {
        metadataRendererContract[tokenId] = metadataRenderer;

        if (initData.length > 0) {
            // metadataRenderer.
        }

        emit UpdatedMetadataRendererForToken(tokenId, msg.sender, metadataRenderer);
    }

    function adminMint(address recipient, uint256 tokenId, uint256 quantity, bytes memory data) public canMint(tokenId, quantity) nonReentrant {
        // First check token specific role
        if (!_isAdminOrRole(msg.sender, tokenId, PERMISSION_BIT_MINTER)) {
            // Then check admin role
            _requireAdminOrRole(msg.sender, CONTRACT_BASE_ID, PERMISSION_BIT_MINTER);
        }
        _mint(recipient, tokenId, quantity, data);
    }

    function adminMintBatch(address recipient, uint256[] memory tokenIds, uint256[] memory quantities, bytes memory data) public nonReentrant {
        bool isGlobalAdminOrMinter = _isAdminOrRole(msg.sender, CONTRACT_BASE_ID, PERMISSION_BIT_MINTER);

        for (uint256 i = 0; i < tokenIds.length; ++i) {
            if (!isGlobalAdminOrMinter) {
                uint256 checkingTokenId = tokenIds[i];
                _requireAdminOrRole(msg.sender, checkingTokenId, PERMISSION_BIT_MINTER);
            }
            requireCanMintQuantity(tokenIds[i], quantities[i]);
        }
        _mintBatch(recipient, tokenIds, quantities, data);
    }

    function executeCommands(Command[] calldata commands) internal {}

    // Only allow minting one token id at time
    function purchase(
        address minter,
        uint256 tokenId,
        uint256 quantity,
        bytes calldata minterArguments
    ) external payable onlyAdminOrRole(tokenId, PERMISSION_BIT_MINTER) canMint(tokenId, quantity) {
        // Get value sent and handle mint fee
        uint256 ethValueSent = _handleFeeAndGetValueSent();

        // executeCommands(
        IMinter1155(minter).requestMint(address(this), tokenId, quantity, ethValueSent, minterArguments);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(CreatorRoyaltiesControl, ERC1155Upgradeable) returns (bool) {
        return super.supportsInterface(interfaceId) || interfaceId == type(IZoraCreator1155).interfaceId;
    }

    function _mint(address account, uint256 id, uint256 amount, bytes memory data) internal virtual override {
        super._mint(account, id, amount, data);
        tokens[id].totalSupply += amount;
    }

    function _mintBatch(address to, uint256[] memory ids, uint256[] memory amounts, bytes memory data) internal virtual override {
        super._mintBatch(to, ids, amounts, data);
        for (uint256 i = 0; i < ids.length; ++i) {
            tokens[ids[i]].totalSupply += amounts[i];
        }
    }

    /// ETH Withdraw Functions ///

    function withdrawAll() public onlyAdminOrRole(CONTRACT_BASE_ID, PERMISSION_BIT_FUNDS_MANAGER) {
        uint256 contractValue = address(this).balance;
        if (!TransferHelperUtils.safeSendETH(msg.sender, contractValue)) {
            revert ETHWithdrawFailed(msg.sender, contractValue);
        }
    }

    function withdrawCustom(address recipient, uint256 amount) public onlyAdminOrRole(CONTRACT_BASE_ID, PERMISSION_BIT_FUNDS_MANAGER) {
        uint256 contractValue = address(this).balance;
        if (amount == 0) {
            amount = contractValue;
        }
        if (amount > contractValue) {
            revert FundsWithdrawInsolvent(amount, contractValue);
        }

        if (!TransferHelperUtils.safeSendETH(recipient, amount)) {
            revert ETHWithdrawFailed(recipient, amount);
        }
    }

    ///                                                          ///
    ///                         MANAGER UPGRADE                  ///
    ///                                                          ///

    /// @notice Ensures the caller is authorized to upgrade the contract
    /// @dev This function is called in `upgradeTo` & `upgradeToAndCall`
    /// @param _newImpl The new implementation address
    function _authorizeUpgrade(address _newImpl) internal override onlyAdmin(CONTRACT_BASE_ID) {}
}
