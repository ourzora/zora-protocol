// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IZoraCreator1155} from "../interfaces/IZoraCreator1155.sol";
import {PublicMulticall} from "../utils/PublicMulticall.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {ERC1155Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import {ZoraCreator1155StorageV1} from "./ZoraCreator1155StorageV1.sol";
import {IMinter1155} from "../interfaces/IMinter1155.sol";
import {IRenderer1155} from "../interfaces/IRenderer1155.sol";
import {ICreatorCommands} from "../interfaces/ICreatorCommands.sol";
import {CreatorPermissionControl} from "../permissions/CreatorPermissionControl.sol";
import {CreatorRoyaltiesControl} from "../royalties/CreatorRoyaltiesControl.sol";
import {SharedBaseConstants} from "../shared/SharedBaseConstants.sol";
import {TransferHelperUtils} from "../utils/TransferHelperUtils.sol";
import {MintFeeManager} from "../fee/MintFeeManager.sol";
import {CreatorRendererControl} from "../renderer/CreatorRendererControl.sol";

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract ZoraCreator1155Impl is
    IZoraCreator1155,
    ReentrancyGuardUpgradeable,
    PublicMulticall,
    ERC1155Upgradeable,
    MintFeeManager,
    UUPSUpgradeable,
    CreatorRendererControl,
    ZoraCreator1155StorageV1,
    CreatorPermissionControl,
    CreatorRoyaltiesControl
{
    uint256 public immutable PERMISSION_BIT_ADMIN = 2**1;
    uint256 public immutable PERMISSION_BIT_MINTER = 2**2;
    uint256 public immutable PERMISSION_BIT_SALES = 2**3;
    uint256 public immutable PERMISSION_BIT_METADATA = 2**4;
    uint256 public immutable PERMISSION_BIT_FUNDS_MANAGER = 2**5;

    constructor(uint256 _mintFeeBPS, address _mintFeeRecipient) MintFeeManager(_mintFeeBPS, _mintFeeRecipient) initializer {}

    function contractVersion() external pure override returns (string memory) {
        return "0.0.1";
    }

    function initialize(
        string memory newContractURI,
        RoyaltyConfiguration memory defaultRoyaltyConfiguration,
        address defaultAdmin,
        bytes[] calldata setupActions
    ) external initializer {
        // Initialize OZ 1155 implementation
        __ERC1155_init("");

        // Setup re-entracy guard
        __ReentrancyGuard_init();

        // Setup uups
        // TODO this does nothing and costs gas, remove?
        __UUPSUpgradeable_init();

        // Setup contract-default token ID
        _setupDefaultToken(defaultAdmin, newContractURI, defaultRoyaltyConfiguration);

        // Set owner to default admin
        _setOwner(defaultAdmin);

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

    function _setupDefaultToken(
        address defaultAdmin,
        string memory newContractURI,
        RoyaltyConfiguration memory defaultRoyaltyConfiguration
    ) internal {
        // Add admin permission to default admin to manage contract
        _addPermission(CONTRACT_BASE_ID, defaultAdmin, PERMISSION_BIT_ADMIN);

        // Mint token ID 0 / don't allow any user mints
        _setupNewToken(newContractURI, 0);

        // Update default royalties
        _updateRoyalties(CONTRACT_BASE_ID, defaultRoyaltyConfiguration);
    }

    function updateRoyaltiesForToken(uint256 tokenId, RoyaltyConfiguration memory newConfiguration)
        external
        onlyAdminOrRole(tokenId, PERMISSION_BIT_FUNDS_MANAGER)
    {
        _updateRoyalties(tokenId, newConfiguration);
    }

    // remove from openzeppelin impl
    function _setURI(string memory newuri) internal virtual override {}

    function _getNextTokenId() internal returns (uint256) {
        unchecked {
            return nextTokenId++;
        }
    }

    function _isAdminOrRole(
        address user,
        uint256 tokenId,
        uint256 role
    ) internal view returns (bool) {
        return _hasPermission(tokenId, user, PERMISSION_BIT_ADMIN | role);
    }

    function isAdminOrRole(
        address user,
        uint256 tokenId,
        uint256 role
    ) external view returns (bool) {
        return _isAdminOrRole(user, tokenId, role);
    }

    function _requireAdminOrRole(
        address user,
        uint256 tokenId,
        uint256 role
    ) internal view {
        if (!(_hasPermission(tokenId, user, PERMISSION_BIT_ADMIN | role) || _hasPermission(CONTRACT_BASE_ID, user, PERMISSION_BIT_ADMIN))) {
            revert UserMissingRoleForToken(user, tokenId, role);
        }
    }

    function _requireAdmin(address user, uint256 tokenId) internal view {
        if (!(_hasPermission(tokenId, user, PERMISSION_BIT_ADMIN) || _hasPermission(CONTRACT_BASE_ID, user, PERMISSION_BIT_ADMIN))) {
            revert UserMissingRoleForToken(user, tokenId, PERMISSION_BIT_ADMIN);
        }
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

    modifier canMintQuantity(uint256 tokenId, uint256 quantity) {
        requireCanMintQuantity(tokenId, quantity);
        _;
    }

    function setupNewToken(string memory _uri, uint256 maxSupply)
        public
        onlyAdminOrRole(CONTRACT_BASE_ID, PERMISSION_BIT_MINTER)
        nonReentrant
        returns (uint256)
    {
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

    function adminMint(
        address recipient,
        uint256 tokenId,
        uint256 quantity,
        bytes memory data
    ) external onlyAdminOrRole(tokenId, PERMISSION_BIT_MINTER) {
        // Call internal admin mint
        _adminMint(recipient, tokenId, quantity, data);
    }

    function addPermission(
        uint256 tokenId,
        address user,
        uint256 permissionBits
    ) external onlyAdmin(tokenId) {
        _addPermission(tokenId, user, permissionBits);
    }

    function removePermission(
        uint256 tokenId,
        address user,
        uint256 permissionBits
    ) external onlyAdmin(tokenId) {
        _removePermission(tokenId, user, permissionBits);

        // Clear owner field
        if (tokenId == CONTRACT_BASE_ID && user == owner && !_hasPermission(CONTRACT_BASE_ID, user, PERMISSION_BIT_ADMIN)) {
            _setOwner(address(0));
        }
    }

    function setOwner(address newOwner) external onlyAdmin(CONTRACT_BASE_ID) {
        if (!_hasPermission(CONTRACT_BASE_ID, newOwner, PERMISSION_BIT_ADMIN)) {
            revert NewOwnerNeedsToBeAdmin();
        }
        // Update owner field
        _setOwner(newOwner);
    }

    function _setOwner(address newOwner) internal {
        address lastOwner = owner;
        owner = newOwner;

        emit OwnershipTransferred(lastOwner, newOwner);
    }

    /// @notice AdminMint that only checks if the requested quantity can be minted and has a re-entrant guard
    function _adminMint(
        address recipient,
        uint256 tokenId,
        uint256 quantity,
        bytes memory data
    ) internal  nonReentrant {
        _mint(recipient, tokenId, quantity, data);
    }

    function adminMintBatch(
        address recipient,
        uint256[] memory tokenIds,
        uint256[] memory quantities,
        bytes memory data
    ) public nonReentrant {
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

    // Only allow minting one token id at time
    function purchase(
        IMinter1155 minter,
        uint256 tokenId,
        uint256 quantity,
        bytes calldata minterArguments
    ) external payable {
        // Require admin from the minter to mint
        _requireAdminOrRole(address(minter), tokenId, PERMISSION_BIT_MINTER);

        // Get value sent and handle mint fee
        uint256 ethValueSent = _handleFeeAndGetValueSent();

        // Execute commands returned from minter
        _executeCommands(minter.requestMint(address(this), tokenId, quantity, ethValueSent, minterArguments).commands, ethValueSent, tokenId);
    }

    function setTokenMetadataRenderer(
        uint256 tokenId,
        IRenderer1155 renderer,
        bytes calldata setupData
    ) external onlyAdminOrRole(tokenId, PERMISSION_BIT_METADATA) {
        _setRenderer(tokenId, renderer, setupData);
    }

    /// Execute Minter Commands ///

    function _executeCommands(
        ICreatorCommands.Command[] memory commands,
        uint256 ethValueSent,
        uint256 tokenId
    ) internal {
        for (uint256 i = 0; i < commands.length; ++i) {
            ICreatorCommands.CreatorActions method = commands[i].method;
            if (method == ICreatorCommands.CreatorActions.SEND_ETH) {
                (address recipient, uint256 amount) = abi.decode(commands[i].args, (address, uint256));
                if (ethValueSent > amount) {
                    revert Mint_InsolventSaleTransfer();
                }
                if (!TransferHelperUtils.safeSendETH(recipient, amount)) {
                    revert Mint_ValueTransferFail();
                }
            } else if (method == ICreatorCommands.CreatorActions.MINT) {
                (address recipient, uint256 mintTokenId, uint256 quantity) = abi.decode(commands[i].args, (address, uint256, uint256));
                if (tokenId != 0 && mintTokenId != tokenId) {
                    revert Mint_TokenIDMintNotAllowed();
                }
                _adminMint(recipient, tokenId, quantity, "");
            } else if (method == ICreatorCommands.CreatorActions.NO_OP) {
                // no-op
            } else {
                revert Mint_UnknownCommand();
            }
        }
    }

    /// Proxy Setter for Sale Updates ///

    function callSale(
        uint256 tokenId,
        IMinter1155 salesConfig,
        bytes memory data
    ) external onlyAdminOrRole(tokenId, PERMISSION_BIT_SALES) {
        _requireAdminOrRole(address(salesConfig), tokenId, PERMISSION_BIT_MINTER);
        (bool success, ) = address(salesConfig).call(data);
        if (!success) {
            revert Sale_CallFailed();
        }
    }

    /// Proxy setter for renderer updates ///

    function callRenderer(uint256 tokenId, bytes memory data) external onlyAdminOrRole(tokenId, PERMISSION_BIT_METADATA) {
        (bool success, ) = address(getCustomRenderer(tokenId)).call(data);
        if (!success) {
            revert Metadata_CallFailed();
        }
    }

    /// Getter for supports interface ///
    function supportsInterface(bytes4 interfaceId) public view virtual override(CreatorRoyaltiesControl, ERC1155Upgradeable) returns (bool) {
        return super.supportsInterface(interfaceId) || interfaceId == type(IZoraCreator1155).interfaceId;
    }

    /// Generic 1155 function overrides ///

    function _mint(
        address account,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) internal virtual override {
        super._mint(account, id, amount, data);
        tokens[id].totalSupply += amount;
    }

    function _mintBatch(
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal virtual override {
        super._mintBatch(to, ids, amounts, data);
        for (uint256 i = 0; i < ids.length; ++i) {
            tokens[ids[i]].totalSupply += amounts[i];
        }
    }

    /// Metadata Getter Functions ///

    function contractURI() external view returns (string memory) {
        return uri(0);
    }

    function uri(uint256 tokenId) public view override returns (string memory) {
        if (bytes(tokens[tokenId].uri).length > 0) {
            return tokens[tokenId].uri;
        }
        return _render(tokenId);
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
