// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IProtocolRewards} from "@zoralabs/protocol-rewards/src/interfaces/IProtocolRewards.sol";
import {IERC20Minter} from "../../interfaces/IERC20Minter.sol";
import {LimitedMintPerAddress} from "../../minters/utils/LimitedMintPerAddress.sol";
import {SaleStrategy} from "../../minters/SaleStrategy.sol";
import {ICreatorCommands} from "../../interfaces/ICreatorCommands.sol";
import {ERC20MinterRewards} from "./ERC20MinterRewards.sol";
import {IZora1155} from "./IZora1155.sol";

/*


             ░░░░░░░░░░░░░░              
        ░░▒▒░░░░░░░░░░░░░░░░░░░░        
      ░░▒▒▒▒░░░░░░░░░░░░░░░░░░░░░░      
    ░░▒▒▒▒░░░░░░░░░░░░░░    ░░░░░░░░    
   ░▓▓▒▒▒▒░░░░░░░░░░░░        ░░░░░░░    
  ░▓▓▓▒▒▒▒░░░░░░░░░░░░        ░░░░░░░░  
  ░▓▓▓▒▒▒▒░░░░░░░░░░░░░░    ░░░░░░░░░░  
  ░▓▓▓▒▒▒▒▒▒░░░░░░░░░░░░░░░░░░░░░░░░░░░  
  ░▓▓▓▓▓▒▒▒▒░░░░░░░░░░░░░░░░░░░░░░░░░░  
   ░▓▓▓▓▒▒▒▒▒▒░░░░░░░░░░░░░░░░░░░░░░░  
    ░░▓▓▓▓▒▒▒▒▒▒░░░░░░░░░░░░░░░░░░░░    
    ░░▓▓▓▓▓▓▒▒▒▒▒▒▒▒░░░░░░░░░▒▒▒▒▒░░    
      ░░▓▓▓▓▓▓▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒░░      
          ░░▓▓▓▓▓▓▓▓▓▓▓▓▒▒░░░          

               OURS TRULY,


    github.com/ourzora/zora-protocol

*/

/// @title ERC20Minter
/// @notice Allows for ZoraCreator Mints to be purchased using ERC20 tokens
/// @dev While this contract _looks_ like a minter, we need to be able to directly manage ERC20 tokens. Therefore, we need to establish minter permissions but instead of using the `requestMint` flow we directly request tokens to be minted in order to safely handle the incoming ERC20 tokens.
/// @author @isabellasmallcombe
contract ERC20Minter is ReentrancyGuard, IERC20Minter, SaleStrategy, LimitedMintPerAddress, ERC20MinterRewards {
    using SafeERC20 for IERC20;

    /// @notice The address of the Zora rewards recipient
    address public zoraRewardRecipientAddress;

    /// @notice The ERC20 sale configuration for a given 1155 token
    /// @dev 1155 token address => 1155 token id => SalesConfig
    mapping(address => mapping(uint256 => SalesConfig)) internal salesConfigs;

    /// @notice Initializes the contract with a Zora rewards recipient address
    /// @dev Allows deterministic contract address, called on deploy
    function initialize(address _zoraRewardRecipientAddress) external {
        if (_zoraRewardRecipientAddress == address(0)) {
            revert AddressZero();
        }

        if (zoraRewardRecipientAddress != address(0)) {
            revert AlreadyInitialized();
        }

        zoraRewardRecipientAddress = _zoraRewardRecipientAddress;

        emit ERC20MinterInitialized(TOTAL_REWARD_PCT);
    }

    /// @notice Computes the total reward value for a given amount of ERC20 tokens
    /// @param totalValue The total number of ERC20 tokens
    function computeTotalReward(uint256 totalValue) public pure returns (uint256) {
        return (totalValue * TOTAL_REWARD_PCT) / BPS_TO_PERCENT_2_DECIMAL_PERCISION;
    }

    /// @notice Computes the rewards value given an amount and a reward percentage
    /// @param totalReward The total reward to be distributed
    /// @param rewardPct The percentage of the reward to be distributed
    function computeReward(uint256 totalReward, uint256 rewardPct) public pure returns (uint256) {
        return (totalReward * rewardPct) / BPS_TO_PERCENT_8_DECIMAL_PERCISION;
    }

    /// @notice Computes the rewards for an ERC20 mint
    /// @param totalReward The total reward to be distributed
    function computePaidMintRewards(uint256 totalReward) public pure returns (RewardsSettings memory) {
        uint256 createReferralReward = computeReward(totalReward, CREATE_REFERRAL_PAID_MINT_REWARD_PCT);
        uint256 mintReferralReward = computeReward(totalReward, MINT_REFERRAL_PAID_MINT_REWARD_PCT);
        uint256 firstMinterReward = computeReward(totalReward, FIRST_MINTER_REWARD_PCT);
        uint256 zoraReward = totalReward - (createReferralReward + mintReferralReward + firstMinterReward);

        return
            RewardsSettings({
                createReferralReward: createReferralReward,
                mintReferralReward: mintReferralReward,
                zoraReward: zoraReward,
                firstMinterReward: firstMinterReward
            });
    }

    /// @notice Gets the create referral address for a given token
    /// @param tokenContract The address of the token contract
    /// @param tokenId The ID of the token
    function getCreateReferral(address tokenContract, uint256 tokenId) public view returns (address createReferral) {
        try IZora1155(tokenContract).createReferrals(tokenId) returns (address contractCreateReferral) {
            createReferral = contractCreateReferral;
        } catch {}

        if (createReferral == address(0)) {
            createReferral = zoraRewardRecipientAddress;
        }
    }

    /// @notice Gets the first minter address for a given token
    /// @param tokenContract The address of the token contract
    /// @param tokenId The ID of the token
    function getFirstMinter(address tokenContract, uint256 tokenId) public view returns (address firstMinter) {
        try IZora1155(tokenContract).firstMinters(tokenId) returns (address contractFirstMinter) {
            firstMinter = contractFirstMinter;

            if (firstMinter == address(0)) {
                firstMinter = IZora1155(tokenContract).getCreatorRewardRecipient(tokenId);
            }
        } catch {
            firstMinter = zoraRewardRecipientAddress;
        }
    }

    /// @notice Handles the incoming transfer of ERC20 tokens
    /// @param currency The address of the currency to use for the mint
    /// @param totalValue The total value of the mint
    function _handleIncomingTransfer(address currency, uint256 totalValue) internal {
        uint256 beforeBalance = IERC20(currency).balanceOf(address(this));
        IERC20(currency).safeTransferFrom(msg.sender, address(this), totalValue);
        uint256 afterBalance = IERC20(currency).balanceOf(address(this));

        if ((beforeBalance + totalValue) != afterBalance) {
            revert ERC20TransferSlippage();
        }
    }

    /// @notice Distributes the rewards to the appropriate addresses
    /// @param totalReward The total reward to be distributed
    /// @param currency The currency used for the mint
    /// @param tokenId The ID of the token to mint
    /// @param tokenAddress The address of the token to mint
    /// @param mintReferral The address of the mint referral
    function _distributeRewards(uint256 totalReward, address currency, uint256 tokenId, address tokenAddress, address mintReferral) private {
        RewardsSettings memory settings = computePaidMintRewards(totalReward);

        address createReferral = getCreateReferral(tokenAddress, tokenId);
        address firstMinter = getFirstMinter(tokenAddress, tokenId);

        if (mintReferral == address(0)) {
            mintReferral = zoraRewardRecipientAddress;
        }

        IERC20(currency).safeTransfer(createReferral, settings.createReferralReward);
        IERC20(currency).safeTransfer(firstMinter, settings.firstMinterReward);
        IERC20(currency).safeTransfer(mintReferral, settings.mintReferralReward);
        IERC20(currency).safeTransfer(zoraRewardRecipientAddress, settings.zoraReward);

        emit ERC20RewardsDeposit(
            createReferral,
            mintReferral,
            firstMinter,
            zoraRewardRecipientAddress,
            tokenAddress,
            currency,
            tokenId,
            settings.createReferralReward,
            settings.mintReferralReward,
            settings.firstMinterReward,
            settings.zoraReward
        );
    }

    /// @notice Mints a token using an ERC20 currency, note the total value must have been approved prior to calling this function
    /// @param mintTo The address to mint the token to
    /// @param quantity The quantity of tokens to mint
    /// @param tokenAddress The address of the token to mint
    /// @param tokenId The ID of the token to mint
    /// @param totalValue The total value of the mint
    /// @param currency The address of the currency to use for the mint
    /// @param mintReferral The address of the mint referral
    /// @param comment The optional mint comment
    function mint(
        address mintTo,
        uint256 quantity,
        address tokenAddress,
        uint256 tokenId,
        uint256 totalValue,
        address currency,
        address mintReferral,
        string calldata comment
    ) external nonReentrant {
        SalesConfig storage config = salesConfigs[tokenAddress][tokenId];

        if (config.currency == address(0) || config.currency != currency) {
            revert InvalidCurrency();
        }

        if (totalValue != (config.pricePerToken * quantity)) {
            revert WrongValueSent();
        }

        if (block.timestamp < config.saleStart) {
            revert SaleHasNotStarted();
        }

        if (block.timestamp > config.saleEnd) {
            revert SaleEnded();
        }

        if (config.maxTokensPerAddress > 0) {
            _requireMintNotOverLimitAndUpdate(config.maxTokensPerAddress, quantity, tokenAddress, tokenId, mintTo);
        }

        _handleIncomingTransfer(currency, totalValue);

        IZora1155(tokenAddress).adminMint(mintTo, tokenId, quantity, "");

        uint256 totalReward = computeTotalReward(totalValue);

        _distributeRewards(totalReward, currency, tokenId, tokenAddress, mintReferral);

        IERC20(config.currency).safeTransfer(config.fundsRecipient, totalValue - totalReward);

        if (bytes(comment).length > 0) {
            emit MintComment(mintTo, tokenAddress, tokenId, quantity, comment);
        }
    }

    /// @notice The percentage of the total value that is distributed as rewards
    function totalRewardPct() external pure returns (uint256) {
        return TOTAL_REWARD_PCT;
    }

    /// @notice The URI of the contract
    function contractURI() external pure returns (string memory) {
        return "https://github.com/ourzora/zora-protocol/";
    }

    /// @notice The name of the contract
    function contractName() external pure returns (string memory) {
        return "ERC20 Minter";
    }

    /// @notice The version of the contract
    function contractVersion() external pure returns (string memory) {
        return "1.0.0";
    }

    /// @notice Sets the sale config for a given token
    function setSale(uint256 tokenId, SalesConfig memory salesConfig) external {
        if (salesConfig.pricePerToken < MIN_PRICE_PER_TOKEN) {
            revert PricePerTokenTooLow();
        }
        if (salesConfig.currency == address(0)) {
            revert AddressZero();
        }
        if (salesConfig.fundsRecipient == address(0)) {
            revert AddressZero();
        }

        salesConfigs[msg.sender][tokenId] = salesConfig;

        // Emit event
        emit SaleSet(msg.sender, tokenId, salesConfig);
    }

    /// @notice Deletes the sale config for a given token
    function resetSale(uint256 tokenId) external override {
        delete salesConfigs[msg.sender][tokenId];

        // Deleted sale emit event
        emit SaleSet(msg.sender, tokenId, salesConfigs[msg.sender][tokenId]);
    }

    /// @notice Returns the sale config for a given token
    function sale(address tokenContract, uint256 tokenId) external view returns (SalesConfig memory) {
        return salesConfigs[tokenContract][tokenId];
    }

    /// @notice IERC165 interface support
    function supportsInterface(bytes4 interfaceId) public pure virtual override(LimitedMintPerAddress, SaleStrategy) returns (bool) {
        return super.supportsInterface(interfaceId) || LimitedMintPerAddress.supportsInterface(interfaceId) || SaleStrategy.supportsInterface(interfaceId);
    }

    /// @notice Reverts as `requestMint` is not used in the ERC20 minter. Call `mint` instead.
    function requestMint(address, uint256, uint256, uint256, bytes calldata) external pure returns (ICreatorCommands.CommandSet memory) {
        revert RequestMintInvalidUseMint();
    }

    /// @notice Set the Zora rewards recipient address
    /// @param recipient The new recipient address
    function setZoraRewardsRecipient(address recipient) external {
        if (msg.sender != zoraRewardRecipientAddress) {
            revert OnlyZoraRewardsRecipient();
        }

        if (recipient == address(0)) {
            revert AddressZero();
        }

        emit ZoraRewardsRecipientSet(zoraRewardRecipientAddress, recipient);

        zoraRewardRecipientAddress = recipient;
    }
}
