// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Minter} from "../../interfaces/IERC20Minter.sol";
import {IMinterPremintSetup} from "../../interfaces/IMinterPremintSetup.sol";
import {LimitedMintPerAddress} from "../../minters/utils/LimitedMintPerAddress.sol";
import {SaleStrategy} from "../../minters/SaleStrategy.sol";
import {ICreatorCommands} from "../../interfaces/ICreatorCommands.sol";
import {ERC20MinterRewards} from "./ERC20MinterRewards.sol";
import {IZora1155} from "./IZora1155.sol";
import {TransferHelperUtils} from "../../utils/TransferHelperUtils.sol";
import {Initializable} from "@zoralabs/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {Ownable2StepUpgradeable} from "../../utils/ownable/Ownable2StepUpgradeable.sol";

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
contract ERC20Minter is ReentrancyGuard, IERC20Minter, SaleStrategy, LimitedMintPerAddress, ERC20MinterRewards, Initializable, Ownable2StepUpgradeable {
    using SafeERC20 for IERC20;

    /// @notice The ERC20 minter configuration
    ERC20MinterConfig public minterConfig;

    /// @notice The ERC20 sale configuration for a given 1155 token
    /// @dev 1155 token address => 1155 token id => SalesConfig
    mapping(address => mapping(uint256 => SalesConfig)) internal salesConfigs;

    /// @notice Initializes the contract with a Zora rewards recipient address
    /// @dev Allows deterministic contract address, called on deploy
    function initialize(address _zoraRewardRecipientAddress, address _owner, uint256 _rewardPct, uint256 _ethReward) external initializer {
        __Ownable_init(_owner);
        _setERC20MinterConfig(
            ERC20MinterConfig({zoraRewardRecipientAddress: _zoraRewardRecipientAddress, rewardRecipientPercentage: _rewardPct, ethReward: _ethReward})
        );
    }

    /// @notice Computes the total reward value for a given amount of ERC20 tokens
    /// @param totalValue The total number of ERC20 tokens
    function computeTotalReward(uint256 totalValue) public view returns (uint256) {
        return (totalValue * minterConfig.rewardRecipientPercentage) / BPS_TO_PERCENT_2_DECIMAL_PERCISION;
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
            createReferral = minterConfig.zoraRewardRecipientAddress;
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
            firstMinter = minterConfig.zoraRewardRecipientAddress;
        }
    }

    /// @notice Gets the ERC20MinterConfig
    function getERC20MinterConfig() external view returns (ERC20MinterConfig memory) {
        return minterConfig;
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
            mintReferral = minterConfig.zoraRewardRecipientAddress;
        }

        IERC20(currency).safeTransfer(createReferral, settings.createReferralReward);
        IERC20(currency).safeTransfer(firstMinter, settings.firstMinterReward);
        IERC20(currency).safeTransfer(mintReferral, settings.mintReferralReward);
        IERC20(currency).safeTransfer(minterConfig.zoraRewardRecipientAddress, settings.zoraReward);

        emit ERC20RewardsDeposit(
            createReferral,
            mintReferral,
            firstMinter,
            minterConfig.zoraRewardRecipientAddress,
            tokenAddress,
            currency,
            tokenId,
            settings.createReferralReward,
            settings.mintReferralReward,
            settings.firstMinterReward,
            settings.zoraReward
        );
    }

    /// @notice Distributes the ETH rewards to the Zora rewards recipient
    /// @param ethSent The amount of ETH to distribute
    function _distributeEthRewards(uint256 ethSent) private {
        if (!TransferHelperUtils.safeSendETH(minterConfig.zoraRewardRecipientAddress, ethSent, TransferHelperUtils.FUNDS_SEND_NORMAL_GAS_LIMIT)) {
            revert FailedToSendEthReward();
        }
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
    ) external payable nonReentrant {
        if (msg.value != minterConfig.ethReward * quantity) {
            revert InvalidETHValue(minterConfig.ethReward * quantity, msg.value);
        }

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

        _distributeEthRewards(msg.value);

        IERC20(config.currency).safeTransfer(config.fundsRecipient, totalValue - totalReward);

        if (bytes(comment).length > 0) {
            emit MintComment(mintTo, tokenAddress, tokenId, quantity, comment);
        }
    }

    /// @notice The percentage of the total value that is distributed as rewards
    function totalRewardPct() external view returns (uint256) {
        return minterConfig.rewardRecipientPercentage;
    }

    /// @notice The amount of ETH distributed as rewards
    function ethRewardAmount() external view returns (uint256) {
        return minterConfig.ethReward;
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
        return "2.0.0";
    }

    /// @notice Sets the sale config for a given token
    /// @param tokenId The ID of the token to set the sale config for
    /// @param salesConfig The sale config to set
    function setSale(uint256 tokenId, SalesConfig memory salesConfig) public {
        _requireNotAddressZero(salesConfig.currency);
        _requireNotAddressZero(salesConfig.fundsRecipient);

        if (salesConfig.pricePerToken < MIN_PRICE_PER_TOKEN) {
            revert PricePerTokenTooLow();
        }

        salesConfigs[msg.sender][tokenId] = salesConfig;

        // Emit event
        emit SaleSet(msg.sender, tokenId, salesConfig);
    }

    /// @notice Dynamically builds a SalesConfig from a PremintSalesConfig taking into consideration the current block timestamp
    /// and the PremintSalesConfig's duration.
    /// @param config The PremintSalesConfig to build the SalesConfig from
    function buildSalesConfigForPremint(PremintSalesConfig memory config) public view returns (ERC20Minter.SalesConfig memory) {
        uint64 saleStart = uint64(block.timestamp);
        uint64 saleEnd = config.duration == 0 ? type(uint64).max : saleStart + config.duration;
        return
            IERC20Minter.SalesConfig({
                saleStart: saleStart,
                saleEnd: saleEnd,
                maxTokensPerAddress: config.maxTokensPerAddress,
                pricePerToken: config.pricePerToken,
                fundsRecipient: config.fundsRecipient,
                currency: config.currency
            });
    }

    /// @notice Sets the sales config based for the msg.sender on the tokenId from the abi encoded premint sales config by
    /// abi decoding it and dynamically building the SalesConfig. The saleStart will be the current block timestamp
    /// and saleEnd will be the current block timestamp + the duration in the PremintSalesConfig.
    /// @param tokenId The ID of the token to set the sale config for
    /// @param encodedPremintSalesConfig The abi encoded PremintSalesConfig
    function setPremintSale(uint256 tokenId, bytes calldata encodedPremintSalesConfig) external override {
        PremintSalesConfig memory premintSalesConfig = abi.decode(encodedPremintSalesConfig, (PremintSalesConfig));
        SalesConfig memory salesConfig = buildSalesConfigForPremint(premintSalesConfig);

        setSale(tokenId, salesConfig);
    }

    /// @notice Deletes the sale config for a given token
    /// @param tokenId The ID of the token to reset the sale config for
    function resetSale(uint256 tokenId) external override {
        delete salesConfigs[msg.sender][tokenId];

        // Deleted sale emit event
        emit SaleSet(msg.sender, tokenId, salesConfigs[msg.sender][tokenId]);
    }

    /// @notice Returns the sale config for a given token
    /// @param tokenContract The TokenContract address
    /// @param tokenId The ID of the token to get the sale config for
    function sale(address tokenContract, uint256 tokenId) external view returns (SalesConfig memory) {
        return salesConfigs[tokenContract][tokenId];
    }

    /// @notice IERC165 interface support
    /// @param interfaceId The interface ID to check
    function supportsInterface(bytes4 interfaceId) public pure virtual override(LimitedMintPerAddress, SaleStrategy) returns (bool) {
        return
            super.supportsInterface(interfaceId) ||
            LimitedMintPerAddress.supportsInterface(interfaceId) ||
            SaleStrategy.supportsInterface(interfaceId) ||
            interfaceId == type(IMinterPremintSetup).interfaceId;
    }

    /// @notice Reverts as `requestMint` is not used in the ERC20 minter. Call `mint` instead.
    function requestMint(address, uint256, uint256, uint256, bytes calldata) external pure returns (ICreatorCommands.CommandSet memory) {
        revert RequestMintInvalidUseMint();
    }

    /// @notice Sets the ERC20MinterConfig
    /// @param _config The ERC20MinterConfig to set
    function _setERC20MinterConfig(ERC20MinterConfig memory _config) internal {
        _requireNotAddressZero(_config.zoraRewardRecipientAddress);

        if (_config.rewardRecipientPercentage > 100) {
            revert InvalidValue();
        }

        minterConfig = _config;
        emit ERC20MinterConfigSet(_config);
    }

    /// @notice Sets the ERC20MinterConfig
    /// @param config The ERC20MinterConfig to set
    function setERC20MinterConfig(ERC20MinterConfig memory config) external onlyOwner {
        _setERC20MinterConfig(config);
    }

    /// @notice Reverts if the address is address(0)
    /// @param _address The address to check
    function _requireNotAddressZero(address _address) internal pure {
        if (_address == address(0)) {
            revert AddressZero();
        }
    }
}
