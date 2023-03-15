// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/interfaces/IERC165Upgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {ERC1155Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC1155MetadataURIUpgradeable} from "@openzeppelin/contracts-upgradeable/interfaces/IERC1155MetadataURIUpgradeable.sol";
import {IZoraCreator1155} from "../interfaces/IZoraCreator1155.sol";
import {PublicMulticall} from "../utils/PublicMulticall.sol";
import {ZoraCreator1155StorageV1} from "./ZoraCreator1155StorageV1.sol";
import {IMinter1155} from "../interfaces/IMinter1155.sol";
import {IRenderer1155} from "../interfaces/IRenderer1155.sol";
import {ICreatorCommands} from "../interfaces/ICreatorCommands.sol";
import {CreatorPermissionControl} from "../permissions/CreatorPermissionControl.sol";
import {CreatorRoyaltiesControl} from "../royalties/CreatorRoyaltiesControl.sol";
import {SharedBaseConstants} from "../shared/SharedBaseConstants.sol";
import {TransferHelperUtils} from "../utils/TransferHelperUtils.sol";
import {MintFeeManager} from "../fee/MintFeeManager.sol";
import {LegacyNamingControl} from "../legacy-naming/LegacyNamingControl.sol";
import {CreatorRendererControl} from "../renderer/CreatorRendererControl.sol";

import {ContractVersionBase} from "../version/ContractVersionBase.sol";

/// @title ZoraCreator1155Impl
/// @notice The core implementation contract for a creator's 1155 token
contract ZoraCreator1155Impl is
    IZoraCreator1155,
    ContractVersionBase,
    ReentrancyGuardUpgradeable,
    PublicMulticall,
    ERC1155Upgradeable,
    MintFeeManager,
    UUPSUpgradeable,
    CreatorRendererControl,
    LegacyNamingControl,
    ZoraCreator1155StorageV1,
    CreatorPermissionControl,
    CreatorRoyaltiesControl
{
    uint256 public immutable PERMISSION_BIT_ADMIN = 2**1;
    uint256 public immutable PERMISSION_BIT_MINTER = 2**2;

    // option @tyson remove all of these until we need them
    uint256 public immutable PERMISSION_BIT_SALES = 2**3;
    uint256 public immutable PERMISSION_BIT_METADATA = 2**4;
    uint256 public immutable PERMISSION_BIT_FUNDS_MANAGER = 2**5;

    constructor(uint256 _mintFeeAmount, address _mintFeeRecipient) MintFeeManager(_mintFeeAmount, _mintFeeRecipient) initializer {}

    /// @notice Initializes the contract
    /// @param newContractURI The contract URI
    /// @param defaultRoyaltyConfiguration The default royalty configuration
    /// @param defaultAdmin The default admin to manage the token
    /// @param setupActions The setup actions to run, if any
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
            _removePermission(CONTRACT_BASE_ID, msg.sender, PERMISSION_BIT_ADMIN);
        }
    }

    /// @notice sets up the global configuration for the 1155 contract
    /// @param newContractURI The contract URI
    /// @param defaultRoyaltyConfiguration The default royalty configuration
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

    /// @notice Updates the royalty configuration for a token
    /// @param tokenId The token ID to update
    /// @param newConfiguration The new royalty configuration
    function updateRoyaltiesForToken(uint256 tokenId, RoyaltyConfiguration memory newConfiguration)
        external
        onlyAdminOrRole(tokenId, PERMISSION_BIT_FUNDS_MANAGER)
    {
        _updateRoyalties(tokenId, newConfiguration);
    }

    /// @notice remove this function from openzeppelin impl
    /// @dev This makes this internal function a no-op
    function _setURI(string memory newuri) internal virtual override {}

    /// @notice This gets the next token in line to be minted when minting linearly (default behavior) and updates the counter
    function _getAndUpdateNextTokenId() internal returns (uint256) {
        unchecked {
            return nextTokenId++;
        }
    }

    /// @notice Ensure that the next token ID is correct
    /// @dev This reverts if the invariant doesn't match. This is used for multicall token id assumptions
    /// @param lastTokenId The last token ID
    function assumeLastTokenIdMatches(uint256 lastTokenId) external view {
        unchecked {
            if (nextTokenId - 1 != lastTokenId) {
                revert TokenIdMismatch(lastTokenId, nextTokenId - 1);
            }
        }
    }

    /// @notice Checks if a user either has a role for a token or if they are the admin
    /// @dev This is an internal function that is called by the external getter and internal functions
    /// @param user The user to check
    /// @param tokenId The token ID to check
    /// @param role The role to check
    /// @return true or false if the permission exists for the user given the token id
    function _isAdminOrRole(address user, uint256 tokenId, uint256 role) internal view returns (bool) {
        return _hasAnyPermission(tokenId, user, PERMISSION_BIT_ADMIN | role);
    }

    /// @notice Checks if a user either has a role for a token or if they are the admin
    /// @param user The user to check
    /// @param tokenId The token ID to check
    /// @param role The role to check
    /// @return true or false if the permission exists for the user given the token id
    function isAdminOrRole(address user, uint256 tokenId, uint256 role) external view returns (bool) {
        return _isAdminOrRole(user, tokenId, role);
    }

    /// @notice Checks if the user is an admin for the given tokenId
    /// @dev This function reverts if the permission does not exist for the given user and tokenId
    /// @param user user to check
    /// @param tokenId tokenId to check
    /// @param role role to check for admin
    function _requireAdminOrRole(address user, uint256 tokenId, uint256 role) internal view {
        if (!(_hasAnyPermission(tokenId, user, PERMISSION_BIT_ADMIN | role) || _hasAnyPermission(CONTRACT_BASE_ID, user, PERMISSION_BIT_ADMIN))) {
            revert UserMissingRoleForToken(user, tokenId, role);
        }
    }

    /// @notice Checks if the user is an admin
    /// @dev This reverts if the user is not an admin for the given token id or contract
    /// @param user user to check
    /// @param tokenId tokenId to check
    /// @return true or false if the permission exists for the user given the token id
    function _requireAdmin(address user, uint256 tokenId) internal view {
        if (!(_hasAnyPermission(tokenId, user, PERMISSION_BIT_ADMIN) || _hasAnyPermission(CONTRACT_BASE_ID, user, PERMISSION_BIT_ADMIN))) {
            revert UserMissingRoleForToken(user, tokenId, PERMISSION_BIT_ADMIN);
        }
    }

    /// @notice Modifier checking if the user is an admin or has a role
    /// @dev This reverts if the msg.sender is not an admin for the given token id or contract
    /// @param tokenId tokenId to check
    /// @param role role to check
    modifier onlyAdminOrRole(uint256 tokenId, uint256 role) {
        _requireAdminOrRole(msg.sender, tokenId, role);
        _;
    }

    /// @notice Modifier checking if the user is an admin
    /// @dev This reverts if the msg.sender is not an admin for the given token id or contract
    /// @param tokenId tokenId to check
    modifier onlyAdmin(uint256 tokenId) {
        _requireAdmin(msg.sender, tokenId);
        _;
    }

    /// @notice Modifier checking if the requested quantity of tokens can be minted for the tokenId
    /// @dev This reverts if the number that can be minted is exceeded
    /// @param tokenId token id to check available allowed quantity
    /// @param quantity requested to be minted
    modifier canMintQuantity(uint256 tokenId, uint256 quantity) {
        _requireCanMintQuantity(tokenId, quantity);
        _;
    }

    /// @notice Only from approved address for burn
    /// @param from address that the tokens will be burned from, validate that this is msg.sender or that msg.sender is approved
    modifier onlyFromApprovedForBurn(address from) {
        if (from != msg.sender && !isApprovedForAll(from, msg.sender)) {
            revert Burn_NotOwnerOrApproved(msg.sender, from);
        }

        _;
    }

    /// @notice Checks if a user can mint a quantity of a token
    /// @dev Reverts if the mint exceeds the allowed quantity (or if the token does not exist)
    /// @param tokenId The token ID to check
    /// @param quantity The quantity of tokens to mint to check
    function _requireCanMintQuantity(uint256 tokenId, uint256 quantity) internal view {
        TokenData memory tokenInformation = tokens[tokenId];
        if (tokenInformation.totalMinted + quantity > tokenInformation.maxSupply) {
            revert CannotMintMoreTokens(tokenId, quantity, tokenInformation.totalMinted, tokenInformation.maxSupply);
        }
    }

    /// @notice Set up a new token
    /// @param _uri The URI for the token (underscore since `uri()` is reserved by OpenZeppelin)
    /// @param maxSupply The maximum supply of the token
    function setupNewToken(string memory _uri, uint256 maxSupply)
        public
        onlyAdminOrRole(CONTRACT_BASE_ID, PERMISSION_BIT_MINTER)
        nonReentrant
        returns (uint256)
    {
        // TODO(iain): isMaxSupply = 0 open edition or maybe uint256(max) - 1
        //                                                  0xffffffff -> 2**8*4 4.2bil
        //                                                  0xf0000000 -> 2**8*4-(8*3)

        uint256 tokenId = _setupNewToken(_uri, maxSupply);
        // Allow the token creator to administrate this token
        _addPermission(tokenId, msg.sender, PERMISSION_BIT_ADMIN);
        if (bytes(_uri).length > 0) {
            emit URI(_uri, tokenId);
        }

        emit SetupNewToken(tokenId, msg.sender, _uri, maxSupply);

        return tokenId;
    }

    /// @notice Update the token URI for a token
    /// @param tokenId The token ID to update the URI for
    /// @param _newURI The new URI
    function updateTokenURI(uint256 tokenId, string memory _newURI) external onlyAdminOrRole(tokenId, PERMISSION_BIT_METADATA) {
        if (tokenId == CONTRACT_BASE_ID) {
            revert NotAllowedContractBaseIDUpdate();
        }
        emit URI(_newURI, tokenId);
        tokens[tokenId].uri = _newURI;
    }

    /// @notice Update the global contract metadata
    /// @param _newURI The new contract URI
    /// @param _newName The new contract name
    function updateContractMetadata(string memory _newURI, string memory _newName) external onlyAdminOrRole(0, PERMISSION_BIT_METADATA) {
        tokens[CONTRACT_BASE_ID].uri = _newURI;
        _setName(_newName);
        emit ContractMetadataUpdated(msg.sender, _newURI, _newName);
    }

    function _setupNewToken(string memory _uri, uint256 maxSupply) internal returns (uint256 tokenId) {
        tokenId = _getAndUpdateNextTokenId();
        TokenData memory tokenData = TokenData({uri: _uri, maxSupply: maxSupply, totalMinted: 0});
        tokens[tokenId] = tokenData;
        emit UpdatedToken(msg.sender, tokenId, tokenData);
    }

    /// @notice Add a role to a user for a token
    /// @param tokenId The token ID to add the role to
    /// @param user The user to add the role to
    /// @param permissionBits The permission bit to add
    function addPermission(
        uint256 tokenId,
        address user,
        uint256 permissionBits
    ) external onlyAdmin(tokenId) {
        _addPermission(tokenId, user, permissionBits);
    }

    /// @notice Remove a role from a user for a token
    /// @param tokenId The token ID to remove the role from
    /// @param user The user to remove the role from
    /// @param permissionBits The permission bit to remove
    function removePermission(
        uint256 tokenId,
        address user,
        uint256 permissionBits
    ) external onlyAdmin(tokenId) {
        _removePermission(tokenId, user, permissionBits);

        // Clear owner field
        if (tokenId == CONTRACT_BASE_ID && user == owner && !_hasAnyPermission(CONTRACT_BASE_ID, user, PERMISSION_BIT_ADMIN)) {
            _setOwner(address(0));
        }
    }

    /// @notice Set the owner of the contract
    /// @param newOwner The new owner of the contract
    function setOwner(address newOwner) external onlyAdmin(CONTRACT_BASE_ID) {
        if (!_hasAnyPermission(CONTRACT_BASE_ID, newOwner, PERMISSION_BIT_ADMIN)) {
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
    /// @param recipient recipient for admin minted tokens 
    /// @param tokenId token id to mint
    /// @param quantity quantity to mint
    /// @param data callback data as specified by the 1155 spec
    function _adminMint(address recipient, uint256 tokenId, uint256 quantity, bytes memory data) internal nonReentrant {
        _mint(recipient, tokenId, quantity, data);
    }

    /// @notice Mint a token to a user as the admin or minter
    /// @param recipient The recipient of the token
    /// @param tokenId The token ID to mint
    /// @param quantity The quantity of tokens to mint
    /// @param data The data to pass to the onERC1155Received function
    function adminMint(
        address recipient,
        uint256 tokenId,
        uint256 quantity,
        bytes memory data
    ) external onlyAdminOrRole(tokenId, PERMISSION_BIT_MINTER) {
        // Call internal admin mint
        _adminMint(recipient, tokenId, quantity, data);
    }

    /// @notice Batch mint tokens to a user as the admin or minter
    /// @param recipient The recipient of the tokens
    /// @param tokenIds The token IDs to mint
    /// @param quantities The quantities of tokens to mint
    /// @param data The data to pass to the onERC1155BatchReceived function
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
            _requireCanMintQuantity(tokenIds[i], quantities[i]);
        }
        _mintBatch(recipient, tokenIds, quantities, data);
    }

    /// @notice Mint tokens given a minter contract and minter arguments
    /// @param minter The minter contract to use
    /// @param tokenId The token ID to mint
    /// @param quantity The quantity of tokens to mint
    /// @param minterArguments The arguments to pass to the minter
    function mint(IMinter1155 minter, uint256 tokenId, uint256 quantity, bytes calldata minterArguments) external payable {
        // Require admin from the minter to mint
        _requireAdminOrRole(address(minter), tokenId, PERMISSION_BIT_MINTER);

        // Get value sent and handle mint fee
        uint256 ethValueSent = _handleFeeAndGetValueSent(quantity);

        // Execute commands returned from minter
        _executeCommands(minter.requestMint(address(this), tokenId, quantity, ethValueSent, minterArguments).commands, ethValueSent, tokenId);

        emit Purchased(msg.sender, address(minter), tokenId, quantity, msg.value);
    }

    /// @notice Set a metadata renderer for a token
    /// @param tokenId The token ID to set the renderer for
    /// @param renderer The renderer to set
    /// @param setupData The data to pass to the renderer upon intialization
    function setTokenMetadataRenderer(
        uint256 tokenId,
        IRenderer1155 renderer,
        bytes calldata setupData
    ) external onlyAdminOrRole(tokenId, PERMISSION_BIT_METADATA) {
        _setRenderer(tokenId, renderer, setupData);

        if (tokenId == 0) {
            emit ContractRendererUpdated(renderer);
        } else {
            // We don't know the uri from the renderer but can emit a notification to the indexer here
            emit URI("", tokenId);
        }
    }

    /// Execute Minter Commands ///

    /// @notice Internal functions to execute commands returned by the minter
    /// @param commands list of command structs 
    /// @param ethValueSent the ethereum value sent in the mint transaction into the contract
    /// @param tokenId the token id the user requested to mint (0 if the token id is set by the minter itself across the whole contract)
    function _executeCommands(ICreatorCommands.Command[] memory commands, uint256 ethValueSent, uint256 tokenId) internal {
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

    /// @notice Token info getter
    /// @param tokenId token id to get info for
    /// @return TokenData struct returned
    function getTokenInfo(uint256 tokenId) external view returns (TokenData memory) {
        return tokens[tokenId];
    }

    /// @notice Proxy setter for sale contracts (only callable by SALES permission or admin)
    /// @param tokenId The token ID to call the sale contract with
    /// @param salesConfig The sales config contract to call
    /// @param data The data to pass to the sales config contract
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

    /// @notice Proxy setter for renderer contracts (only callable by METADATA permission or admin)
    /// @param tokenId The token ID to call the renderer contract with
    /// @param data The data to pass to the renderer contract
    function callRenderer(uint256 tokenId, bytes memory data) external onlyAdminOrRole(tokenId, PERMISSION_BIT_METADATA) {
        // We assume any renderers set are checked for EIP165 signature during write stage. 
        (bool success, bytes memory why) = address(getCustomRenderer(tokenId)).call(data);
        if (!success) {
            revert Renderer_CallFailed(why);
        }
    }

    /// @notice Returns true if the contract implements the interface defined by interfaceId
    /// @param interfaceId The interface to check for
    /// @return if the interfaceId is marked as supported
    function supportsInterface(bytes4 interfaceId) public view virtual override(CreatorRoyaltiesControl, ERC1155Upgradeable) returns (bool) {
        return super.supportsInterface(interfaceId) || interfaceId == type(IZoraCreator1155).interfaceId;
    }

    /// Generic 1155 function overrides ///

    /// @notice Mint function that 1) checks quantity and 2) handles supply royalty 3) keeps track of allowed tokens
    /// @param to to mint to
    /// @param id token id to mint
    /// @param amount of tokens to mint
    /// @param data as specified by 1155 standard
    function _mint(address to, uint256 id, uint256 amount, bytes memory data) internal virtual override {
        (address supplyRoyaltyRecipient, uint256 supplyRoyaltyAmount) = supplyRoyaltyInfo(id, tokens[id].totalMinted, amount);

        _requireCanMintQuantity(id, amount + supplyRoyaltyAmount);

        super._mint(to, id, amount, data);
        if (supplyRoyaltyAmount > 0) {
            super._mint(supplyRoyaltyRecipient, id, supplyRoyaltyAmount, data);
        }
        tokens[id].totalMinted += amount + supplyRoyaltyAmount;
    }

    /// @notice Mint batch function that 1) checks quantity and 2) handles supply royalty 3) keeps track of allowed tokens
    /// @param to to mint to
    /// @param ids token ids to mint
    /// @param amounts of tokens to mint
    /// @param data as specified by 1155 standard
    function _mintBatch(address to, uint256[] memory ids, uint256[] memory amounts, bytes memory data) internal virtual override {
        super._mintBatch(to, ids, amounts, data);

        for (uint256 i = 0; i < ids.length; ++i) {
            (address supplyRoyaltyRecipient, uint256 supplyRoyaltyAmount) = supplyRoyaltyInfo(ids[i], tokens[ids[i]].totalMinted, amounts[i]);
            _requireCanMintQuantity(ids[i], amounts[i] + supplyRoyaltyAmount);
            if (supplyRoyaltyAmount > 0) {
                super._mint(supplyRoyaltyRecipient, ids[i], supplyRoyaltyAmount, data);
            }
            tokens[ids[i]].totalMinted += amounts[i] + supplyRoyaltyAmount;
        }
    }

    /// @dev Only the current owner is allowed to burn
    /// @notice Burns a token
    /// @param from the user to burn from
    /// @param tokenId The token ID to burn
    /// @param amount The amount of tokens to burn
    function burn(
        address from,
        uint256 tokenId,
        uint256 amount
    ) external onlyFromApprovedForBurn(from) {
        _burn(from, tokenId, amount);
    }

    /// @notice Burns a batch of tokens
    /// @dev Only the current owner is allowed to burn
    /// @param from the user to burn from
    /// @param tokenIds The token ID to burn
    /// @param amounts The amount of tokens to burn
    function burnBatch(
        address from,
        uint256[] calldata tokenIds,
        uint256[] calldata amounts
    ) external onlyFromApprovedForBurn(from) {
        _burnBatch(from, tokenIds, amounts);
    }

    /// @notice Returns the URI for the contract
    function contractURI() external view returns (string memory) {
        return uri(0);
    }

    /// @notice Returns the URI for a token
    /// @param tokenId The token ID to return the URI for
    function uri(uint256 tokenId) public view override(ERC1155Upgradeable, IERC1155MetadataURIUpgradeable) returns (string memory) {
        if (bytes(tokens[tokenId].uri).length > 0) {
            return tokens[tokenId].uri;
        }
        return _render(tokenId);
    }

    /// @notice Withdraws all ETH from the contract to the message sender
    function withdrawAll() public onlyAdminOrRole(CONTRACT_BASE_ID, PERMISSION_BIT_FUNDS_MANAGER) {
        uint256 contractValue = address(this).balance;
        if (!TransferHelperUtils.safeSendETH(msg.sender, contractValue)) {
            revert ETHWithdrawFailed(msg.sender, contractValue);
        }
    }

    /// @notice Withdraws a specified amount of ETH from the contract to a specified recipient
    /// @param recipient The recipient of the ETH
    /// @param amount The amount of ETH to withdraw
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
