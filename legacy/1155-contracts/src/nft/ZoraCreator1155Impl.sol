// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {ERC1155Upgradeable} from "@zoralabs/openzeppelin-contracts-upgradeable/contracts/token/ERC1155/ERC1155Upgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@zoralabs/openzeppelin-contracts-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";
import {UUPSUpgradeable} from "@zoralabs/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {IERC1155MetadataURIUpgradeable} from "@zoralabs/openzeppelin-contracts-upgradeable/contracts/interfaces/IERC1155MetadataURIUpgradeable.sol";
import {IERC165Upgradeable} from "@zoralabs/openzeppelin-contracts-upgradeable/contracts/interfaces/IERC165Upgradeable.sol";
import {IProtocolRewards} from "@zoralabs/shared-contracts/interfaces/IProtocolRewards.sol";
import {RewardSplits, RewardSplitsLib} from "@zoralabs/protocol-rewards/src/abstract/RewardSplits.sol";
import {ERC1155RewardsStorageV1} from "@zoralabs/protocol-rewards/src/abstract/ERC1155/ERC1155RewardsStorageV1.sol";
import {ReentrancyGuardUpgradeable} from "@zoralabs/openzeppelin-contracts-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";
import {UUPSUpgradeable} from "@zoralabs/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {MathUpgradeable} from "@zoralabs/openzeppelin-contracts-upgradeable/contracts/utils/math/MathUpgradeable.sol";

import {IZoraCreator1155} from "../interfaces/IZoraCreator1155.sol";
import {IZoraCreator1155Initializer} from "../interfaces/IZoraCreator1155Initializer.sol";
import {IERC7572} from "../interfaces/IERC7572.sol";
import {ContractVersionBase} from "../version/ContractVersionBase.sol";
import {CreatorPermissionControl} from "../permissions/CreatorPermissionControl.sol";
import {CreatorRendererControl} from "../renderer/CreatorRendererControl.sol";
import {CreatorRoyaltiesControl} from "../royalties/CreatorRoyaltiesControl.sol";
import {ICreatorCommands} from "../interfaces/ICreatorCommands.sol";
import {IMinter1155} from "../interfaces/IMinter1155.sol";
import {IRenderer1155} from "../interfaces/IRenderer1155.sol";
import {ITransferHookReceiver} from "../interfaces/ITransferHookReceiver.sol";
import {IUpgradeGate} from "../interfaces/IUpgradeGate.sol";
import {IZoraCreator1155} from "../interfaces/IZoraCreator1155.sol";
import {LegacyNamingControl} from "../legacy-naming/LegacyNamingControl.sol";
import {PublicMulticall} from "../utils/PublicMulticall.sol";
import {SharedBaseConstants} from "../shared/SharedBaseConstants.sol";
import {TransferHelperUtils} from "../utils/TransferHelperUtils.sol";
import {ZoraCreator1155StorageV1} from "./ZoraCreator1155StorageV1.sol";
import {IZoraCreator1155Errors} from "../interfaces/IZoraCreator1155Errors.sol";
import {ERC1155DelegationStorageV1} from "../delegation/ERC1155DelegationStorageV1.sol";
import {IZoraCreator1155DelegatedCreation, ISupportsAABasedDelegatedTokenCreation, IHasSupportedPremintSignatureVersions} from "../interfaces/IZoraCreator1155DelegatedCreation.sol";
import {IMintWithRewardsRecipients} from "../interfaces/IMintWithRewardsRecipients.sol";
import {IHasContractName} from "../interfaces/IContractMetadata.sol";
import {ZoraCreator1155Attribution, DecodedCreatorAttribution, PremintTokenSetup, PremintConfigV2, DelegatedTokenCreation, DelegatedTokenSetup} from "../delegation/ZoraCreator1155Attribution.sol";
import {ContractCreationConfig, PremintConfig} from "@zoralabs/shared-contracts/entities/Premint.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {IReduceSupply} from "@zoralabs/shared-contracts/interfaces/IReduceSupply.sol";

/// Imagine. Mint. Enjoy.
/// @title ZoraCreator1155Impl
/// @notice The core implementation contract for a creator's 1155 token
/// @author @iainnash / @tbtstl
contract ZoraCreator1155Impl is
    IZoraCreator1155,
    IZoraCreator1155Initializer,
    ContractVersionBase,
    ReentrancyGuardUpgradeable,
    PublicMulticall,
    ERC1155Upgradeable,
    UUPSUpgradeable,
    CreatorRendererControl,
    LegacyNamingControl,
    ZoraCreator1155StorageV1,
    CreatorPermissionControl,
    CreatorRoyaltiesControl,
    RewardSplits,
    ERC1155RewardsStorageV1,
    IERC7572,
    IHasContractName,
    ERC1155DelegationStorageV1
{
    /// @notice This user role allows for any action to be performed
    uint256 public constant PERMISSION_BIT_ADMIN = 2 ** 1;
    /// @notice This user role allows for only mint actions to be performed
    uint256 public constant PERMISSION_BIT_MINTER = 2 ** 2;

    /// @notice This user role allows for only managing sales configurations
    uint256 public constant PERMISSION_BIT_SALES = 2 ** 3;
    /// @notice This user role allows for only managing metadata configuration
    uint256 public constant PERMISSION_BIT_METADATA = 2 ** 4;
    /// @notice This user role allows for only withdrawing funds and setting funds withdraw address
    uint256 public constant PERMISSION_BIT_FUNDS_MANAGER = 2 ** 5;
    /// @notice Factory contract
    IUpgradeGate internal immutable upgradeGate;
    /// @notice Timed sale strategy allowed to reduce supply
    address internal immutable timedSaleStrategy;

    uint256 constant MINT_FEE = 0.000111 ether;

    /// @notice This is the immutable constructor for defining onchain addresses that is updated on contract updates
    /// @param _mintFeeRecipient Recipient for the mint fee (used in rewards) (cannot be 0)
    /// @param _upgradeGate Address to register the upgrade gate for these contracts (cannot be 0)
    /// @param _protocolRewards Protocol rewards contract ddress (cannot be 0)
    /// @param _timedSaleStrategy Timed sale strategy – used to control access to reduceSupply, can be 0 for when this contract is not supported
    constructor(
        address _mintFeeRecipient,
        address _upgradeGate,
        address _protocolRewards,
        address _timedSaleStrategy
    ) RewardSplits(_protocolRewards, _mintFeeRecipient) initializer {
        if (address(_upgradeGate) == address(0)) {
            revert INVALID_ADDRESS_ZERO();
        }

        upgradeGate = IUpgradeGate(_upgradeGate);
        timedSaleStrategy = _timedSaleStrategy;
    }

    /// @notice Initializes the contract
    /// @param contractName the legacy on-chain contract name
    /// @param newContractURI The contract URI
    /// @param defaultRoyaltyConfiguration The default royalty configuration
    /// @param defaultAdmin The default admin to manage the token
    /// @param setupActions The setup actions to run, if any
    function initialize(
        string memory contractName,
        string memory newContractURI,
        RoyaltyConfiguration memory defaultRoyaltyConfiguration,
        address payable defaultAdmin,
        bytes[] calldata setupActions
    ) external nonReentrant initializer {
        // We are not initializing the OZ 1155 implementation
        // to save contract storage space and runtime
        // since the only thing affected here is the uri.
        // __ERC1155_init("");

        // Setup uups
        __UUPSUpgradeable_init();

        // Setup re-entrancy guard
        __ReentrancyGuard_init();

        // Setup contract-default token ID
        _setupDefaultToken(defaultAdmin, newContractURI, defaultRoyaltyConfiguration);

        // Set owner to default admin
        _setOwner(defaultAdmin);

        _setFundsRecipient(defaultAdmin);

        _setName(contractName);

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
    function _setupDefaultToken(address defaultAdmin, string memory newContractURI, RoyaltyConfiguration memory defaultRoyaltyConfiguration) internal {
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
    function updateRoyaltiesForToken(
        uint256 tokenId,
        RoyaltyConfiguration memory newConfiguration
    ) external onlyAdminOrRole(tokenId, PERMISSION_BIT_FUNDS_MANAGER) {
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
    /// @dev This reverts if the invariant doesn't match. This is used for multil token id assumptions
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
        if (!(_hasAnyPermission(tokenId, user, PERMISSION_BIT_ADMIN | role) || _hasAnyPermission(CONTRACT_BASE_ID, user, PERMISSION_BIT_ADMIN | role))) {
            revert UserMissingRoleForToken(user, tokenId, role);
        }
    }

    /// @notice Checks if the user is an admin
    /// @dev This reverts if the user is not an admin for the given token id or contract
    /// @param user user to check
    /// @param tokenId tokenId to check
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
        TokenData storage tokenInformation = tokens[tokenId];
        if (tokenInformation.totalMinted + quantity > tokenInformation.maxSupply) {
            revert CannotMintMoreTokens(tokenId, quantity, tokenInformation.totalMinted, tokenInformation.maxSupply);
        }
    }

    /// @notice Set up a new token
    /// @param newURI The URI for the token
    /// @param maxSupply The maximum supply of the token
    function setupNewToken(
        string calldata newURI,
        uint256 maxSupply
    ) public onlyAdminOrRole(CONTRACT_BASE_ID, PERMISSION_BIT_MINTER) nonReentrant returns (uint256) {
        uint256 tokenId = _setupNewTokenAndPermission(newURI, maxSupply, msg.sender, PERMISSION_BIT_ADMIN);

        return tokenId;
    }

    /// @notice Set up a new token with a create referral
    /// @param newURI The URI for the token
    /// @param maxSupply The maximum supply of the token
    /// @param createReferral The address of the create referral
    function setupNewTokenWithCreateReferral(
        string calldata newURI,
        uint256 maxSupply,
        address createReferral
    ) public onlyAdminOrRole(CONTRACT_BASE_ID, PERMISSION_BIT_MINTER) nonReentrant returns (uint256) {
        uint256 tokenId = _setupNewTokenAndPermission(newURI, maxSupply, msg.sender, PERMISSION_BIT_ADMIN);

        _setCreateReferral(tokenId, createReferral);

        return tokenId;
    }

    function _setupNewTokenAndPermission(string memory newURI, uint256 maxSupply, address user, uint256 permission) internal returns (uint256) {
        uint256 tokenId = _setupNewToken(newURI, maxSupply);

        _addPermission(tokenId, user, permission);

        if (bytes(newURI).length > 0) {
            emit URI(newURI, tokenId);
        }

        emit SetupNewToken(tokenId, user, newURI, maxSupply);

        return tokenId;
    }

    /// @notice Allow a minter to reduce the max supply of a token.
    /// @dev This allows enforcing that no more new tokens can be minted.
    /// @param tokenId The token id to reduce the supply for
    /// @param newMaxSupply The new max supply
    function reduceSupply(uint256 tokenId, uint256 newMaxSupply) external {
        if (msg.sender != timedSaleStrategy) {
            revert OnlyAllowedForTimedSaleStrategy();
        }

        if (!_hasAnyPermission(tokenId, msg.sender, PERMISSION_BIT_MINTER)) {
            revert OnlyAllowedForRegisteredMinter();
        }

        TokenData storage tokenData = tokens[tokenId];
        if (newMaxSupply < tokenData.totalMinted) {
            revert CannotReduceMaxSupplyBelowMinted();
        }

        tokenData.maxSupply = newMaxSupply;
    }

    /// @notice Update the token URI for a token
    /// @param tokenId The token ID to update the URI for
    /// @param _newURI The new URI
    function updateTokenURI(uint256 tokenId, string memory _newURI) external onlyAdminOrRole(tokenId, PERMISSION_BIT_METADATA) {
        if (tokenId == CONTRACT_BASE_ID) {
            revert();
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
        emit ContractURIUpdated();
    }

    function _setupNewToken(string memory newURI, uint256 maxSupply) internal returns (uint256 tokenId) {
        tokenId = _getAndUpdateNextTokenId();
        TokenData memory tokenData = TokenData({uri: newURI, maxSupply: maxSupply, totalMinted: 0});
        tokens[tokenId] = tokenData;
        emit UpdatedToken(msg.sender, tokenId, tokenData);
    }

    /// @notice Add a role to a user for a token
    /// @param tokenId The token ID to add the role to
    /// @param user The user to add the role to
    /// @param permissionBits The permission bit to add
    function addPermission(uint256 tokenId, address user, uint256 permissionBits) external onlyAdmin(tokenId) {
        _addPermission(tokenId, user, permissionBits);
    }

    /// @notice Remove a role from a user for a token
    /// @param tokenId The token ID to remove the role from
    /// @param user The user to remove the role from
    /// @param permissionBits The permission bit to remove
    function removePermission(uint256 tokenId, address user, uint256 permissionBits) external {
        address sender = msg.sender;

        // Check if the user is an admin if they do not have the roles they are attempting to remove.
        if (!(user == sender && _hasAllPermissions(tokenId, sender, permissionBits))) {
            // Ensure that the sender of this message is an admin
            _requireAdmin(sender, tokenId);
        }

        _removePermission(tokenId, user, permissionBits);

        // Clear owner field on contract if removed permission is owner.
        if (tokenId == CONTRACT_BASE_ID && user == config.owner && !_hasAnyPermission(CONTRACT_BASE_ID, user, PERMISSION_BIT_ADMIN)) {
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

    /// @notice Getter for the owner singleton of the contract for outside interfaces
    /// @return the owner of the contract singleton for compat.
    function owner() external view returns (address) {
        return config.owner;
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
    ) external nonReentrant onlyAdminOrRole(tokenId, PERMISSION_BIT_MINTER) {
        // Mint the specified tokens
        _mint(recipient, tokenId, quantity, data);
    }

    /// @notice Mint tokens and payout rewards given a minter contract, minter arguments, and rewards arguments
    /// @param minter The minter contract to use
    /// @param tokenId The token ID to mint
    /// @param quantity The quantity of tokens to mint
    /// @param rewardsRecipients The addresses of rewards arguments - rewardsRecipients[0] = mintReferral, rewardsRecipients[1] = platformReferral
    /// @param minterArguments The arguments to pass to the minter
    function mint(
        IMinter1155 minter,
        uint256 tokenId,
        uint256 quantity,
        address[] calldata rewardsRecipients,
        bytes calldata minterArguments
    ) external payable nonReentrant {
        _mint(minter, tokenId, quantity, rewardsRecipients, minterArguments);
    }

    function _mintAndHandleRewards(
        IMinter1155 minter,
        address[] memory rewardsRecipients,
        uint256 valueSent,
        uint256 totalReward,
        uint256 tokenId,
        uint256 quantity,
        bytes calldata minterArguments
    ) private {
        uint256 ethValueSent = _handleRewardsAndGetValueRemaining(valueSent, totalReward, tokenId, rewardsRecipients);

        _executeCommands(minter.requestMint(msg.sender, tokenId, quantity, ethValueSent, minterArguments).commands, ethValueSent, tokenId);
        emit Purchased(msg.sender, address(minter), tokenId, quantity, valueSent);
    }

    function _handleRewardsAndGetValueRemaining(
        uint256 totalSentValue,
        uint256 totalReward,
        uint256 tokenId,
        address[] memory rewardsRecipients
    ) internal returns (uint256 valueRemaining) {
        // 1. Get rewards recipients

        // create referral is pulled from storage, if it's not set, defaults to zora reward recipient
        address createReferral = createReferrals[tokenId];
        if (createReferral == address(0)) {
            createReferral = zoraRewardRecipient;
        }

        // mint referral is passed in arguments to minting functions; if it's not set, defaults to zora reward recipient
        address mintReferral = rewardsRecipients.length > 0 ? rewardsRecipients[0] : zoraRewardRecipient;
        if (mintReferral == address(0)) {
            mintReferral = zoraRewardRecipient;
        }

        // creator reward recipient is pulled from storage, if it's not set, defaults to zora reward recipient
        address creatorRewardRecipient = getCreatorRewardRecipient(tokenId);
        if (creatorRewardRecipient == address(0)) {
            creatorRewardRecipient = zoraRewardRecipient;
        }

        // first minter is pulled from storage, if it's not set, defaults to creator reward recipient (which is zora if there is no creator reward recipient set)
        address firstMinter = firstMinters[tokenId];
        if (firstMinter == address(0)) {
            firstMinter = creatorRewardRecipient;
        }

        // 2. Get rewards amounts - which varies if its a paid or free mint

        RewardsSettings memory settings;
        if (totalSentValue < totalReward) {
            revert INVALID_ETH_AMOUNT();
            // if value sent is the same as the reward amount, we assume its a free mint
        } else if (totalSentValue == totalReward) {
            settings = RewardSplitsLib.getRewards(false, totalReward);
            // otherwise, we assume its a paid mint
        } else {
            settings = RewardSplitsLib.getRewards(true, totalReward);

            unchecked {
                valueRemaining = totalSentValue - totalReward;
            }
        }

        // 3. Deposit rewards rewards

        protocolRewards.depositRewards{value: totalReward}(
            // if there was no creator reward amount, 0 out that address
            settings.creatorReward == 0 ? address(0) : creatorRewardRecipient,
            settings.creatorReward,
            createReferral,
            settings.createReferralReward,
            mintReferral,
            settings.mintReferralReward,
            firstMinter,
            settings.firstMinterReward,
            zoraRewardRecipient,
            settings.zoraReward
        );
    }

    function _mint(IMinter1155 minter, uint256 tokenId, uint256 quantity, address[] memory rewardsRecipients, bytes calldata minterArguments) private {
        // Require admin from the minter to mint
        _requireAdminOrRole(address(minter), tokenId, PERMISSION_BIT_MINTER);

        uint256 totalReward = MINT_FEE * quantity;

        _mintAndHandleRewards(minter, rewardsRecipients, msg.value, totalReward, tokenId, quantity, minterArguments);
    }

    function _getTotalMintsQuantity(uint256[] calldata mintTokenIds, uint256[] calldata quantities) private pure returns (uint256 totalQuantity) {
        if (mintTokenIds.length != quantities.length) {
            revert Mint_InvalidMintArrayLength();
        }

        for (uint256 i = 0; i < mintTokenIds.length; i++) {
            totalQuantity += quantities[i];
        }
    }

    function mintFee() external view returns (uint256) {
        return MINT_FEE;
    }

    /// @notice Get the creator reward recipient address for a specific token.
    /// @param tokenId The token id to get the creator reward recipient for
    /// @dev Returns the royalty recipient address for the token if set; otherwise uses the fundsRecipient.
    /// If both are not set, this contract will be set as the recipient, and an account with
    /// `PERMISSION_BIT_FUNDS_MANAGER` will be able to withdraw via the `withdrawFor` function.
    function getCreatorRewardRecipient(uint256 tokenId) public view returns (address) {
        address royaltyRecipient = getRoyalties(tokenId).royaltyRecipient;

        if (royaltyRecipient != address(0)) {
            return royaltyRecipient;
        }

        if (config.fundsRecipient != address(0)) {
            return config.fundsRecipient;
        }

        return address(this);
    }

    /// @notice Set a metadata renderer for a token
    /// @param tokenId The token ID to set the renderer for
    /// @param renderer The renderer to set
    function setTokenMetadataRenderer(uint256 tokenId, IRenderer1155 renderer) external nonReentrant onlyAdminOrRole(tokenId, PERMISSION_BIT_METADATA) {
        _setRenderer(tokenId, renderer);

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
                if (!TransferHelperUtils.safeSendETH(recipient, amount, TransferHelperUtils.FUNDS_SEND_NORMAL_GAS_LIMIT)) {
                    revert Mint_ValueTransferFail();
                }
            } else if (method == ICreatorCommands.CreatorActions.MINT) {
                (address recipient, uint256 mintTokenId, uint256 quantity) = abi.decode(commands[i].args, (address, uint256, uint256));
                if (tokenId != 0 && mintTokenId != tokenId) {
                    revert Mint_TokenIDMintNotAllowed();
                }
                _mint(recipient, tokenId, quantity, "");
            } else {
                // no-op
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
    function callSale(uint256 tokenId, IMinter1155 salesConfig, bytes calldata data) external onlyAdminOrRole(tokenId, PERMISSION_BIT_SALES) {
        _requireAdminOrRole(address(salesConfig), tokenId, PERMISSION_BIT_MINTER);
        if (!salesConfig.supportsInterface(type(IMinter1155).interfaceId)) {
            revert Sale_CannotCallNonSalesContract(address(salesConfig));
        }

        // Get the token id encoded in the calldata for the sales config
        // Assume that it is the first 32 bytes following the function selector
        uint256 encodedTokenId = uint256(bytes32(data[4:36]));

        // Ensure the encoded token id matches the passed token id
        if (encodedTokenId != tokenId) {
            revert IZoraCreator1155Errors.Call_TokenIdMismatch();
        }

        (bool success, bytes memory why) = address(salesConfig).call(data);
        if (!success) {
            revert CallFailed(why);
        }
    }

    /// @notice Proxy setter for renderer contracts (only callable by METADATA permission or admin)
    /// @param tokenId The token ID to call the renderer contract with
    /// @param data The data to pass to the renderer contract
    function callRenderer(uint256 tokenId, bytes memory data) external onlyAdminOrRole(tokenId, PERMISSION_BIT_METADATA) {
        // We assume any renderers set are checked for EIP165 signature during write stage.
        (bool success, bytes memory why) = address(getCustomRenderer(tokenId)).call(data);
        if (!success) {
            revert CallFailed(why);
        }
    }

    /// @notice Returns true if the contract implements the interface defined by interfaceId
    /// @param interfaceId The interface to check for
    /// @return if the interfaceId is marked as supported
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(CreatorRoyaltiesControl, ERC1155Upgradeable, IERC165Upgradeable) returns (bool) {
        return
            super.supportsInterface(interfaceId) ||
            interfaceId == type(IZoraCreator1155).interfaceId ||
            ERC1155Upgradeable.supportsInterface(interfaceId) ||
            interfaceId == type(IHasContractName).interfaceId ||
            interfaceId == type(IHasSupportedPremintSignatureVersions).interfaceId ||
            interfaceId == type(ISupportsAABasedDelegatedTokenCreation).interfaceId ||
            interfaceId == type(IMintWithRewardsRecipients).interfaceId ||
            interfaceId == type(IReduceSupply).interfaceId;
    }

    /// Generic 1155 function overrides ///

    /// @notice Mint function that 1) checks quantity 2) keeps track of allowed tokens
    /// @param to to mint to
    /// @param id token id to mint
    /// @param amount of tokens to mint
    /// @param data as specified by 1155 standard
    function _mint(address to, uint256 id, uint256 amount, bytes memory data) internal virtual override {
        _requireCanMintQuantity(id, amount);

        tokens[id].totalMinted += amount;

        super._mint(to, id, amount, data);
    }

    /// @notice Burns a batch of tokens
    /// @dev Only the current owner is allowed to burn
    /// @param from the user to burn from
    /// @param tokenIds The token ID to burn
    /// @param amounts The amount of tokens to burn
    function burnBatch(address from, uint256[] calldata tokenIds, uint256[] calldata amounts) external {
        if (from != msg.sender && !isApprovedForAll(from, msg.sender)) {
            revert Burn_NotOwnerOrApproved(msg.sender, from);
        }

        _burnBatch(from, tokenIds, amounts);
    }

    function setTransferHook(ITransferHookReceiver transferHook) external onlyAdmin(CONTRACT_BASE_ID) {
        if (address(transferHook) != address(0)) {
            if (!transferHook.supportsInterface(type(ITransferHookReceiver).interfaceId)) {
                revert Config_TransferHookNotSupported(address(transferHook));
            }
        }

        config.transferHook = transferHook;
        emit ConfigUpdated(msg.sender, ConfigUpdate.TRANSFER_HOOK, config);
    }

    /// @notice Hook before token transfer that checks for a transfer hook integration
    /// @param operator operator moving the tokens
    /// @param from from address
    /// @param to to address
    /// @param id token id to move
    /// @param amount amount of token
    /// @param data data of token
    function _beforeTokenTransfer(address operator, address from, address to, uint256 id, uint256 amount, bytes memory data) internal override {
        super._beforeTokenTransfer(operator, from, to, id, amount, data);
        if (address(config.transferHook) != address(0)) {
            config.transferHook.onTokenTransfer(address(this), operator, from, to, id, amount, data);
        }
    }

    /// @notice Hook before token transfer that checks for a transfer hook integration
    /// @param operator operator moving the tokens
    /// @param from from address
    /// @param to to address
    /// @param ids token ids to move
    /// @param amounts amounts of tokens
    /// @param data data of tokens
    function _beforeBatchTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal override {
        super._beforeBatchTokenTransfer(operator, from, to, ids, amounts, data);
        if (address(config.transferHook) != address(0)) {
            config.transferHook.onTokenTransferBatch({target: address(this), operator: operator, from: from, to: to, ids: ids, amounts: amounts, data: data});
        }
    }

    /// @notice Returns the URI for the contract
    function contractURI() external view override(IERC7572, IZoraCreator1155) returns (string memory) {
        IRenderer1155 customRenderer = getCustomRenderer(CONTRACT_BASE_ID);
        if (address(customRenderer) != address(0)) {
            return customRenderer.contractURI();
        }
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

    /// @notice Internal setter for contract admin with no access checks
    /// @param newOwner new owner address
    function _setOwner(address newOwner) internal {
        address lastOwner = config.owner;
        config.owner = newOwner;

        emit OwnershipTransferred(lastOwner, newOwner);
        emit ConfigUpdated(msg.sender, ConfigUpdate.OWNER, config);
    }

    /// @notice Set funds recipient address
    /// @param fundsRecipient new funds recipient address
    function setFundsRecipient(address payable fundsRecipient) external onlyAdminOrRole(CONTRACT_BASE_ID, PERMISSION_BIT_FUNDS_MANAGER) {
        _setFundsRecipient(fundsRecipient);
    }

    /// @notice Internal no-checks set funds recipient address
    /// @param fundsRecipient new funds recipient address
    function _setFundsRecipient(address payable fundsRecipient) internal {
        config.fundsRecipient = fundsRecipient;
        emit ConfigUpdated(msg.sender, ConfigUpdate.FUNDS_RECIPIENT, config);
    }

    /// @notice Allows the create referral to update the address that can claim their rewards
    function updateCreateReferral(uint256 tokenId, address recipient) external {
        if (msg.sender != createReferrals[tokenId]) revert ONLY_CREATE_REFERRAL();

        _setCreateReferral(tokenId, recipient);
    }

    function _setCreateReferral(uint256 tokenId, address recipient) internal {
        createReferrals[tokenId] = recipient;
    }

    /// @notice Withdraws all ETH from the contract to the funds recipient address
    function withdraw() public onlyAdminOrRole(CONTRACT_BASE_ID, PERMISSION_BIT_FUNDS_MANAGER) {
        uint256 contractValue = address(this).balance;
        if (!TransferHelperUtils.safeSendETH(config.fundsRecipient, contractValue, TransferHelperUtils.FUNDS_SEND_NORMAL_GAS_LIMIT)) {
            revert ETHWithdrawFailed(config.fundsRecipient, contractValue);
        }
    }

    receive() external payable {}

    ///                                                          ///
    ///                         MANAGER UPGRADE                  ///
    ///                                                          ///

    /// @notice Ensures the caller is authorized to upgrade the contract
    /// @dev This function is called in `upgradeTo` & `upgradeToAndCall`
    /// @param _newImpl The new implementation address
    function _authorizeUpgrade(address _newImpl) internal view override onlyAdmin(CONTRACT_BASE_ID) {
        if (!upgradeGate.isRegisteredUpgradePath(_getImplementation(), _newImpl)) {
            revert();
        }
    }

    function contractName() external view returns (string memory) {
        return "Zora Creator 1155";
    }

    /// @notice Returns the current implementation address
    function implementation() external view returns (address) {
        return _getImplementation();
    }

    function supportedPremintSignatureVersions() external pure returns (string[] memory) {
        return DelegatedTokenCreation.supportedPremintSignatureVersions();
    }

    /// Sets up a new token using a token configuration and a signature created for the token creation parameters.
    /// The signature must be created by an account with the PERMISSION_BIT_MINTER role on the contract.
    /// @param premintConfig abi encoded configuration of token to be created
    /// @param premintVersion version of the premint configuration
    /// @param signature EIP-712 Signature created on the premintConfig by an account with the PERMISSION_BIT_MINTER role on the contract.
    /// @param firstMinter original sender of the transaction, used to set the firstMinter
    /// @param premintSignerContract if an EIP-1271 based premint, the contract that signed the premint
    function delegateSetupNewToken(
        bytes memory premintConfig,
        bytes32 premintVersion,
        bytes calldata signature,
        address firstMinter,
        address premintSignerContract
    ) external nonReentrant returns (uint256 newTokenId) {
        if (firstMinter == address(0)) {
            revert FirstMinterAddressZero();
        }
        (DelegatedTokenSetup memory params, DecodedCreatorAttribution memory attribution, bytes[] memory tokenSetupActions) = DelegatedTokenCreation
            .decodeAndRecoverDelegatedTokenSetup(premintConfig, premintVersion, signature, address(this), nextTokenId, premintSignerContract);

        // if a token has already been created for a premint config with this uid:
        if (delegatedTokenId[params.uid] != 0) {
            // return its token id
            return delegatedTokenId[params.uid];
        }

        // this is what attributes this token to have been created by the original creator
        emit CreatorAttribution(attribution.structHash, attribution.domainName, attribution.version, attribution.creator, attribution.signature);

        return _delegateSetupNewToken(params, attribution.creator, tokenSetupActions, firstMinter);
    }

    function _delegateSetupNewToken(
        DelegatedTokenSetup memory params,
        address creator,
        bytes[] memory tokenSetupActions,
        address sender
    ) internal returns (uint256 newTokenId) {
        // require that the signer can create new tokens (is a valid creator)
        _requireAdminOrRole(creator, CONTRACT_BASE_ID, PERMISSION_BIT_MINTER);

        // create the new token; msg sender will have PERMISSION_BIT_ADMIN on the new token
        newTokenId = _setupNewTokenAndPermission(params.tokenURI, params.maxSupply, msg.sender, PERMISSION_BIT_ADMIN);

        _setCreateReferral(newTokenId, params.createReferral);

        delegatedTokenId[params.uid] = newTokenId;

        firstMinters[newTokenId] = sender;

        // then invoke them, calling account should be original msg.sender, which has admin on the new token
        _multicallInternal(tokenSetupActions);

        // remove the token creator as admin of the newly created token:
        _removePermission(newTokenId, msg.sender, PERMISSION_BIT_ADMIN);

        // grant the token creator as admin of the newly created token
        _addPermission(newTokenId, creator, PERMISSION_BIT_ADMIN);
    }
}
