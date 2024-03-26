// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IERC20Minter {
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

    /// @notice ERC20MinterInitialized Event
    /// @param rewardPercentage The reward percentage
    event ERC20MinterInitialized(uint256 rewardPercentage);

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

    /// @notice ZoraRewardsRecipientSet Event
    /// @param prevRecipient The previous recipient address
    /// @param newRecipient The new recipient address
    event ZoraRewardsRecipientSet(address indexed prevRecipient, address indexed newRecipient);

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

    /// @notice ERC20Minter is already initialized
    error AlreadyInitialized();

    /// @notice Only the Zora rewards recipient can call this function
    error OnlyZoraRewardsRecipient();

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
    ) external;

    /// @notice Sets the sale config for a given token
    function setSale(uint256 tokenId, SalesConfig memory salesConfig) external;

    /// @notice Returns the sale config for a given token
    function sale(address tokenContract, uint256 tokenId) external view returns (SalesConfig memory);
}
