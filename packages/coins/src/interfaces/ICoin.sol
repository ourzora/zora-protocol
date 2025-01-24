// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/* 
    !!!         !!!         !!!    
    !!!         !!!         !!!    
    !!!         !!!         !!!    
    !!!         !!!         !!!    
    !!!         !!!         !!!    
    !!!         !!!         !!!    

    WOW         WOW         WOW    
*/
interface ICoin {
    /// @notice Thrown when an operation is attempted with a zero address
    error AddressZero();

    /// @notice Thrown when an invalid market type is specified
    error InvalidMarketType();

    /// @notice Thrown when there are insufficient funds for an operation
    error InsufficientFunds();

    /// @notice Thrown when there is insufficient liquidity for a transaction
    error InsufficientLiquidity();

    /// @notice Thrown when the slippage bounds are exceeded during a transaction
    error SlippageBoundsExceeded();

    /// @notice Thrown when the initial order size is too large
    error InitialOrderSizeTooLarge();

    /// @notice Thrown when the msg.value amount does not match the amount of currency sent
    error EthAmountMismatch();

    /// @notice Thrown when the ETH amount is too small for a transaction
    error EthAmountTooSmall();

    /// @notice Thrown when the expected amount of ERC20s transferred does not match the amount received
    error ERC20TransferAmountMismatch();

    /// @notice Thrown when ETH is sent with a buy or sell but the currency is not WETH
    error EthTransferInvalid();

    /// @notice Thrown when an ETH transfer fails
    error EthTransferFailed();

    /// @notice Thrown when an operation is attempted by an entity other than the pool
    error OnlyPool();

    /// @notice Thrown when an operation is attempted by an entity other than WETH
    error OnlyWeth();

    /// @notice Thrown when a market is not yet graduated
    error MarketNotGraduated();

    /// @notice Thrown when a market is already graduated
    error MarketAlreadyGraduated();

    /// @notice Thrown when the lower tick is not less than the maximum tick or not a multiple of 200
    error InvalidCurrencyLowerTick();

    /// @notice Represents the type of market
    enum MarketType {
        BONDING_CURVE,
        UNISWAP_POOL
    }

    /// @notice Represents the state of the market
    struct MarketState {
        MarketType marketType;
        address marketAddress;
    }

    /// @notice The rewards accrued from the market's liquidity position
    struct MarketRewards {
        uint256 totalAmountCurrency;
        uint256 totalAmountCoin;
        uint256 creatorPayoutAmountCurrency;
        uint256 creatorPayoutAmountCoin;
        uint256 platformReferrerAmountCurrency;
        uint256 platformReferrerAmountCoin;
        uint256 protocolAmountCurrency;
        uint256 protocolAmountCoin;
    }

    /// @notice Emitted when market rewards are distributed
    /// @param creatorPayoutAddress The address of the creator payout recipient
    /// @param platformReferrer The address of the platform referrer
    /// @param protocolRewardRecipient The address of the protocol reward recipient
    /// @param currency The address of the currency
    /// @param marketRewards The rewards accrued from the market's liquidity position
    event CoinMarketRewards(
        address indexed creatorPayoutAddress,
        address indexed platformReferrer,
        address protocolRewardRecipient,
        address currency,
        MarketRewards marketRewards
    );

    /// @notice Emitted when coins are bought
    /// @param buyer The address of the buyer
    /// @param recipient The address of the recipient
    /// @param tradeReferrer The address of the trade referrer
    /// @param coinsPurchased The number of coins purchased
    /// @param currency The address of the currency
    /// @param amountFee The fee for the purchase
    /// @param amountSold The amount of the currency sold
    event CoinBuy(
        address indexed buyer,
        address indexed recipient,
        address indexed tradeReferrer,
        uint256 coinsPurchased,
        address currency,
        uint256 amountFee,
        uint256 amountSold,
        string comment // TODO remove after backend approval
    );

    /// @notice Emitted when coins are sold
    /// @param seller The address of the seller
    /// @param recipient The address of the recipient
    /// @param tradeReferrer The address of the trade referrer
    /// @param coinsSold The number of coins sold
    /// @param currency The address of the currency
    /// @param amountFee The fee for the sale
    /// @param amountPurchased The amount of the currency purchased
    event CoinSell(
        address indexed seller,
        address indexed recipient,
        address indexed tradeReferrer,
        uint256 coinsSold,
        address currency,
        uint256 amountFee,
        uint256 amountPurchased,
        string comment // TODO remove after backend approval
    );

    /// @notice Emitted when a coin is transferred
    /// @param sender The address of the sender
    /// @param recipient The address of the recipient
    /// @param amount The amount of coins
    /// @param senderBalance The balance of the sender after the transfer
    /// @param recipientBalance The balance of the recipient after the transfer
    event CoinTransfer(address indexed sender, address indexed recipient, uint256 amount, uint256 senderBalance, uint256 recipientBalance);

    /// @notice Emitted when trade rewards are distributed
    /// @param creatorPayoutRecipient The address of the creator payout recipient
    /// @param platformReferrer The address of the platform referrer
    /// @param tradeReferrer The address of the trade referrer
    /// @param protocolRewardRecipient The address of the protocol reward recipient
    /// @param creatorReward The reward for the creator
    /// @param platformReferrerReward The reward for the platform referrer
    /// @param traderReferrerReward The reward for the trade referrer
    /// @param protocolReward The reward for the protocol
    /// @param currency The address of the currency
    event CoinTradeRewards(
        address indexed creatorPayoutRecipient,
        address indexed platformReferrer,
        address indexed tradeReferrer,
        address protocolRewardRecipient,
        uint256 creatorReward,
        uint256 platformReferrerReward,
        uint256 traderReferrerReward,
        uint256 protocolReward,
        address currency
    );

    /// @notice Emitted when the creator's payout address is updated
    /// @param caller The msg.sender address
    /// @param prevRecipient The previous payout recipient address
    /// @param newRecipient The new payout recipient address
    event CoinPayoutRecipientUpdated(address indexed caller, address indexed prevRecipient, address indexed newRecipient);

    /// @notice Emitted when the contract URI is updated
    /// @param caller The msg.sender address
    /// @param newURI The new contract URI
    /// @param name The coin name
    event ContractMetadataUpdated(address indexed caller, string newURI, string name);

    /// @notice Executes an order to buy coins with ETH
    /// @param recipient The recipient address of the coins
    /// @param tradeReferrer The address of the trade referrer
    /// @param comment A comment associated with the buy order
    /// @param minOrderSize The minimum coins to prevent slippage
    /// @param sqrtPriceLimitX96 The price limit for Uniswap V3 pool swap
    function buy(
        address recipient,
        address /* refundRecipient - deprecated */,
        address tradeReferrer,
        string memory comment,
        MarketType /* expectedMarketType - deprecated */,
        uint256 minOrderSize,
        uint160 sqrtPriceLimitX96
    ) external payable returns (uint256);

    /// @notice Executes an order to sell coins for ETH
    /// @param amount The number of coins to sell
    /// @param recipient The address to receive the ETH
    /// @param tradeReferrer The address of the trade referrer
    /// @param comment A comment associated with the sell order
    /// @param minPayoutSize The minimum ETH payout to prevent slippage
    /// @param sqrtPriceLimitX96 The price limit for Uniswap V3 pool swap
    function sell(
        uint256 amount,
        address recipient,
        address tradeReferrer,
        string memory comment,
        MarketType /* expectedMarketType - deprecated */,
        uint256 minPayoutSize,
        uint160 sqrtPriceLimitX96
    ) external returns (uint256);

    /// @notice Enables a user to burn their tokens
    /// @param amount The amount of tokens to burn
    function burn(uint256 amount) external;

    /// @notice Returns the URI of the token
    /// @return The token URI
    function tokenURI() external view returns (string memory);

    /// @notice Returns the address of the platform referrer
    /// @return The platform referrer's address
    function platformReferrer() external view returns (address);
}
