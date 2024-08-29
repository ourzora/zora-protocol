// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IZoraTimedSaleStrategyV1 {
    struct SalesConfig {
        /// @notice Unix timestamp for the sale start
        uint64 saleStart;
        /// @notice Unix timestamp for the sale end
        uint64 saleEnd;
        /// @notice The ERC20Z name
        string name;
        /// @notice The ERC20Z symbol
        string symbol;
    }

    struct SaleStorage {
        /// @notice The ERC20z address
        address payable erc20zAddress;
        /// @notice The sale start time
        uint64 saleStart;
        /// @notice The Uniswap pool address
        address poolAddress;
        /// @notice The sale end time
        uint64 saleEnd;
        /// @notice Boolean if the secondary market has been launched
        bool secondaryActivated;
    }

    struct ERC20zActivate {
        /// @notice Total Supply of ERC20z tokens
        uint256 finalTotalERC20ZSupply;
        /// @notice ERC20z Reserve price
        uint256 erc20Reserve;
        /// @notice ERC20z Liquidity
        uint256 erc20Liquidity;
        /// @notice Excess amount of ERC20z
        uint256 excessERC20;
        /// @notice Excess amount of 1155
        uint256 excessERC1155;
        /// @notice Additional ERC1155 to mint
        uint256 additionalERC1155ToMint;
        /// @notice Final 1155 Supply
        uint256 final1155Supply;
    }

    struct ZoraTimedSaleStrategyStorage {
        /// @notice The Zora reward recipient
        address zoraRewardRecipient;
        /// @notice The sales mapping
        mapping(address collection => mapping(uint256 tokenId => SaleStorage)) sales;
    }

    struct RewardsSettings {
        /// @notice The sum of all individual rewards
        uint256 totalReward;
        /// @notice Creator reward
        uint256 creatorReward;
        /// @notice Creator referral reward
        uint256 createReferralReward;
        /// @notice Mint referral reward
        uint256 mintReferralReward;
        /// @notice Market reward
        uint256 marketReward;
        /// @notice Zora reward
        uint256 zoraReward;
    }

    /// @notice SaleSet Event
    /// @param collection The collection address
    /// @param tokenId The token ID
    /// @param salesConfig The sales configuration
    /// @param erc20zAddress The ERC20Z address
    /// @param poolAddress The Uniswap pool address
    /// @param mintFee The total fee in eth to mint each token
    event SaleSet(address indexed collection, uint256 indexed tokenId, SalesConfig salesConfig, address erc20zAddress, address poolAddress, uint256 mintFee);

    /// @notice MintComment Event
    /// @param sender The sender of the comment
    /// @param collection The collection address
    /// @param tokenId The token ID
    /// @param quantity The quantity of tokens minted
    /// @param comment The comment
    event MintComment(address indexed sender, address indexed collection, uint256 indexed tokenId, uint256 quantity, string comment);

    /// @notice Emitted when rewards are distributed from this sale strategy
    /// @param creator The creator of the token
    /// @param creatorReward The creator reward
    /// @param createReferral The create referral
    /// @param createReferralReward The create referral reward
    /// @param mintReferral The mint referral
    /// @param mintReferralReward The mint referral reward
    /// @param market The Uniswap market
    /// @param marketReward The Uniswap market reward
    /// @param zoraRecipient The Zora recipient
    /// @param zoraReward The Zora reward
    event ZoraTimedSaleStrategyRewards(
        address indexed collection,
        uint256 indexed tokenId,
        address creator,
        uint256 creatorReward,
        address createReferral,
        uint256 createReferralReward,
        address mintReferral,
        uint256 mintReferralReward,
        address market,
        uint256 marketReward,
        address zoraRecipient,
        uint256 zoraReward
    );

    /// @notice MarketLaunched Event
    /// @param collection The collection address
    /// @param tokenId The token ID
    /// @param erc20zAddress The ERC20Z address
    /// @param poolAddress The Uniswap pool address
    event MarketLaunched(address indexed collection, uint256 indexed tokenId, address erc20zAddress, address poolAddress);

    /// @notice ZoraRewardRecipientUpdated Event
    /// @param prevRecipient The previous Zora reward recipient
    /// @param newRecipient The new Zora reward recipient
    event ZoraRewardRecipientUpdated(address indexed prevRecipient, address indexed newRecipient);

    /// @notice Error thrown when market is attempted to be started with no sales completed
    error NeedsToBeAtLeastOneSaleToStartMarket();

    /// @notice requestMint() is not used in minter, use mint() instead
    error RequestMintInvalidUseMint();

    /// @notice Cannot set address to zero
    error AddressZero();

    /// @notice The wrong value was sent
    error WrongValueSent();

    /// @notice The sale has already been set
    error SaleAlreadySet();

    /// @notice The sale has not started
    error SaleHasNotStarted();

    /// @notice The sale is in progress
    error SaleInProgress();

    /// @notice The sale has ended
    error SaleEnded();

    /// @notice The sale has not been set
    error SaleNotSet();

    /// @notice Insufficient funds
    error InsufficientFunds();

    /// @notice Only the Zora reward recipient
    error OnlyZoraRewardRecipient();

    /// @notice ResetSale is not available in this sale strategy
    error ResetSaleNotAvailable();

    /// @notice Zora Creator 1155 Contract needs to support IReduceSupply
    error ZoraCreator1155ContractNeedsToSupportReduceSupply();

    /// @notice The sale start time cannot be after the sale ends
    error StartTimeCannotBeAfterEndTime();

    /// @notice The sale start time cannot be in the past
    error EndTimeCannotBeInThePast();

    /// @notice The market has already been launched
    error MarketAlreadyLaunched();

    /// @notice Called by an 1155 collection to set the sale config for a given token
    /// @dev Additionally creates an ERC20Z and Uniswap V3 pool for the token
    /// @param tokenId The collection token id to set the sale config for
    /// @param salesConfig The sale config to set
    function setSale(uint256 tokenId, SalesConfig calldata salesConfig) external;

    /// @notice Called by a collector to mint a token
    /// @param mintTo The address to mint the token to
    /// @param quantity The quantity of tokens to mint
    /// @param collection The address of the 1155 token to mint
    /// @param tokenId The ID of the token to mint
    /// @param mintReferral The address of the mint referral
    /// @param comment The optional mint comment
    function mint(address mintTo, uint256 quantity, address collection, uint256 tokenId, address mintReferral, string calldata comment) external payable;

    /// @notice Gets the create referral address for a given token
    /// @param collection The address of the collection
    /// @param tokenId The ID of the token
    function getCreateReferral(address collection, uint256 tokenId) external view returns (address createReferral);

    /// @notice Computes the rewards for a given quantity of tokens
    /// @param quantity The quantity of tokens to compute rewards for
    function computeRewards(uint256 quantity) external returns (RewardsSettings memory);

    /// @notice Update the Zora reward recipient
    function setZoraRewardRecipient(address recipient) external;

    /// @notice Returns the sale config for a given token
    /// @param collection The collection address
    /// @param tokenId The ID of the token to get the sale config for
    function sale(address collection, uint256 tokenId) external view returns (SaleStorage memory);

    /// @notice Calculate the ERC20z activation values
    /// @param collection The collection address
    /// @param tokenId The token ID
    /// @param erc20zAddress The ERC20Z address
    function calculateERC20zActivate(address collection, uint256 tokenId, address erc20zAddress) external view returns (ERC20zActivate memory);

    /// @notice Called by an 1155 collection to update the sale time if the sale has not started or ended.
    /// @param tokenId The 1155 token id
    /// @param newStartTime The new start time for the sale, ignored if the existing sale has already started
    /// @param newEndTime The new end time for the sale
    function updateSale(uint256 tokenId, uint64 newStartTime, uint64 newEndTime) external;

    /// @notice Called by anyone upon the end of a primary sale to launch the secondary market.
    /// @param collection The 1155 collection address
    /// @param tokenId The 1155 token id
    function launchMarket(address collection, uint256 tokenId) external;
}
