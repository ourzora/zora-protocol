// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IMinterPremintSetup} from "./IMinterPremintSetup.sol";

interface IERC20Minter is IMinterPremintSetup {
    struct RewardsSettings {
        /// @notice Amount of the create referral reward
        uint256 createReferralReward;
        /// @notice Amount of the mint referral reward
        uint256 mintReferralReward;
        /// @notice Amount of the zora reward
        uint256 zoraReward;
        /// @notice Amount of the first minter reward
        uint256 firstMinterReward;
    }

    struct SalesConfig {
        /// @notice Unix timestamp for the sale start
        uint64 saleStart;
        /// @notice Unix timestamp for the sale end
        uint64 saleEnd;
        /// @notice Max tokens that can be minted for an address, 0 if unlimited
        uint64 maxTokensPerAddress;
        /// @notice Price per token in ERC20 currency
        uint256 pricePerToken;
        /// @notice Funds recipient (0 if no different funds recipient than the contract global)
        address fundsRecipient;
        /// @notice ERC20 Currency address
        address currency;
    }

    struct PremintSalesConfig {
        /// @notice Duration of the sale
        uint64 duration;
        /// @notice Max tokens that can be minted for an address, `0` if unlimited
        uint64 maxTokensPerAddress;
        /// @notice Price per token in ERC20 currency
        uint256 pricePerToken;
        /// @notice Funds recipient (0 if no different funds recipient than the contract global)
        address fundsRecipient;
        /// @notice ERC20 Currency address
        address currency;
    }

    struct ERC20MinterConfig {
        /// @notice The address of the Zora rewards recipient
        address zoraRewardRecipientAddress;
        /// @notice The reward recipient percentage
        uint256 rewardRecipientPercentage;
        /// @notice The ETH reward amount
        uint256 ethReward;
    }

    /// @notice Rewards Deposit Event
    /// @param createReferral Creator referral address
    /// @param mintReferral Mint referral address
    /// @param firstMinter First minter address
    /// @param zora ZORA recipient address
    /// @param collection The collection address of the token
    /// @param currency Currency used for the deposit
    /// @param tokenId Token ID
    /// @param createReferralReward Creator referral reward
    /// @param mintReferralReward Mint referral amount
    /// @param firstMinterReward First minter amount
    /// @param zoraReward ZORA amount
    event ERC20RewardsDeposit(
        address indexed createReferral,
        address indexed mintReferral,
        address indexed firstMinter,
        address zora,
        address collection,
        address currency,
        uint256 tokenId,
        uint256 createReferralReward,
        uint256 mintReferralReward,
        uint256 firstMinterReward,
        uint256 zoraReward
    );

    /// @notice MintComment Event
    /// @param sender The sender of the comment
    /// @param tokenContract The token contract address
    /// @param tokenId The token ID
    /// @param quantity The quantity of tokens minted
    /// @param comment The comment
    event MintComment(address indexed sender, address indexed tokenContract, uint256 indexed tokenId, uint256 quantity, string comment);

    /// @notice SaleSet Event
    /// @param mediaContract The media contract address
    /// @param tokenId The token ID
    /// @param salesConfig The sales configuration
    event SaleSet(address indexed mediaContract, uint256 indexed tokenId, SalesConfig salesConfig);

    /// @notice ERC20MinterConfigSet Event
    /// @param config The ERC20MinterConfig
    event ERC20MinterConfigSet(ERC20MinterConfig config);

    /// @notice Cannot set address to zero
    error AddressZero();

    /// @notice Cannot set currency address to zero
    error InvalidCurrency();

    /// @notice Price per ERC20 token is too low
    error PricePerTokenTooLow();

    /// @notice requestMint() is not used in ERC20 minter, use mint() instead
    error RequestMintInvalidUseMint();

    /// @notice Sale has already ended
    error SaleEnded();

    /// @notice Sale has not started yet
    error SaleHasNotStarted();

    /// @notice Value sent is incorrect
    error WrongValueSent();

    /// @notice ERC20 transfer slippage
    error ERC20TransferSlippage();

    /// @notice Failed to send ETH reward
    error FailedToSendEthReward();

    /// @notice Invalid value for ETH reward
    /// @param expectedValue The expected value
    /// @param actualValue The actual value
    error InvalidETHValue(uint256 expectedValue, uint256 actualValue);

    /// @notice Invalid value
    error InvalidValue();

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
    ) external payable;

    /// @notice Sets the sale config for a given token
    /// @param tokenId The ID of the token to set the sale config for
    /// @param salesConfig The sale config to set
    function setSale(uint256 tokenId, SalesConfig memory salesConfig) external;

    /// @notice Dynamically builds a SalesConfig from a PremintSalesConfig, taking into consideration the current block timestamp
    /// and the PremintSalesConfig's duration.
    /// @param config The PremintSalesConfig to build the SalesConfig from
    function buildSalesConfigForPremint(PremintSalesConfig memory config) external view returns (SalesConfig memory);

    /// @notice Returns the sale config for a given token
    /// @param tokenContract The TokenContract address
    /// @param tokenId The ID of the token to get the sale config for
    function sale(address tokenContract, uint256 tokenId) external view returns (SalesConfig memory);

    /// @notice Returns the reward recipient percentage
    function totalRewardPct() external view returns (uint256);

    /// @notice Returns the ETH reward amount
    function ethRewardAmount() external view returns (uint256);

    /// @notice Sets the ERC20MinterConfig
    /// @param config The ERC20MinterConfig to set
    function setERC20MinterConfig(ERC20MinterConfig memory config) external;

    /// @notice Gets the ERC20MinterConfig
    function getERC20MinterConfig() external view returns (ERC20MinterConfig memory);

    /// @notice Sets the sales config based for the msg.sender on the tokenId from the abi encoded premint sales config by
    /// abi decoding it and dynamically building the SalesConfig. The saleStart will be the current block timestamp
    /// and saleEnd will be the current block timestamp + the duration in the PremintSalesConfig.
    /// @param tokenId The ID of the token to set the sale config for
    /// @param encodedPremintSalesConfig The abi encoded PremintSalesConfig
    function setPremintSale(uint256 tokenId, bytes calldata encodedPremintSalesConfig) external override;
}
