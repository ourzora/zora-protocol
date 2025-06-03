# `CoinV4.sol`

The `CoinV4` contract is the core contract for the Zora Coins Protocol. It is a non-upgradeable ERC20 contract built on Uniswap V4 that allows for the creation of media coins with advanced hook-based functionality.

## Overview

The `CoinV4` contract implements multiple interfaces:
- `ICoinV4`: Core V4 coin functionality
- `IHasPoolKey`: Provides access to the Uniswap V4 pool key
- `IHasSwapPath`: Enables complex multi-hop reward distribution
- `IERC165`: Standard interface detection
- `IERC7572`: Standard for protocol-specific metadata

Each coin is created with a Uniswap V4 liquidity pool and an advanced hook system that automatically handles fee collection and reward distribution.

## Inheritance Structure

`CoinV4` inherits from `BaseCoin`, which provides core ERC20 functionality, multi-ownership capabilities, and metadata management. The inheritance hierarchy is:

```
CoinV4 → BaseCoin → ERC20PermitUpgradeable → MultiOwnable → ReentrancyGuardUpgradeable → ContractVersionBase
```

## Key Features

- **ERC20 Functionality**: Basic token transfers, approvals, and balance tracking
- **Uniswap V4 Integration**: Built-in hooks for advanced pool management and automatic fee processing
- **Automatic Reward Distribution**: Hooks that collect LP fees, swap them to backing currency, and distribute rewards on every trade
- **Multi-Hop Fee Conversion**: Supports complex swap paths for coins paired with other coins
- **Advanced Pool Configuration**: Support for multiple liquidity positions and sophisticated market curves
- **Metadata Management**: Updatable contract metadata via URI
- **Multi-Ownership**: Support for multiple owners with permission control

## Hook System

The `CoinV4` contract uses the `ZoraV4CoinHook` which automatically executes on every swap to handle reward distribution. The hook has permissions for `afterInitialize` and `afterSwap` operations on the Uniswap V4 pool and performs three key operations:

### 1. Collect LP Fees
On every swap, the hook collects accrued fees from all liquidity positions in the pool using the `V4Liquidity.collectFees` library function. These fees are generated from trading activity and accumulate over time.

### 2. Swap LP Fees to Backing Currency
The collected fees are automatically swapped to the backing currency through optimal swap paths using the `UniV4SwapToCurrency.swapToPath` library function. For example:
- If a coin is paired directly with USDC, fees are swapped directly to USDC
- If a coin is paired with another coin (like a backing coin), the fees follow the swap path: `ContentCoin → BackingCoin → USDC`

### 3. Distribute Rewards
The final backing currency is then distributed to reward recipients using predefined basis points (BPS):
- **Creator**: 50% to the payout recipient (`CREATOR_REWARD_BPS = 5000`)
- **Create Referral**: 15% to the platform that referred the creator (`CREATE_REFERRAL_REWARD_BPS = 1500`)
- **Trade Referral**: 15% to the platform that referred this specific trade (`TRADE_REFERRAL_REWARD_BPS = 1500`)
- **Protocol**: 20% to the ZORA protocol treasury (calculated as the remainder after other distributions)
- **Doppler**: 5% to the governance entity (`DOPPLER_REWARD_BPS = 500`)

All of this happens automatically in a single transaction whenever someone trades the coin.

## Pool Configuration

The pool configuration is defined by the `PoolConfiguration` struct which contains:
```solidity
struct PoolConfiguration {
    uint8 version;           // Configuration version
    uint16 numPositions;     // Number of liquidity positions
    uint24 fee;              // Fee tier for the pool
    int24 tickSpacing;       // Tick spacing for the pool
    uint16[] numDiscoveryPositions;  // Number of discovery positions
    int24[] tickLower;       // Lower tick bounds for positions
    int24[] tickUpper;       // Upper tick bounds for positions
    uint256[] maxDiscoverySupplyShare; // Maximum share for discovery supply
}
```

This configuration allows for custom market curves with multiple liquidity positions.

## Core Functions

### Pool and Configuration

#### getPoolKey

```solidity
function getPoolKey() external view returns (PoolKey memory);
```

Returns the Uniswap V4 pool key associated with this coin, containing pool identification parameters including currencies, fee tier, tick spacing, and hooks.

#### getPoolConfiguration

```solidity
function getPoolConfiguration() external view returns (PoolConfiguration memory);
```

Returns the pool configuration settings including fee structure, tick spacing, number of positions, and liquidity curve parameters.

#### hooks

```solidity
function hooks() external view returns (IHooks);
```

Returns the hooks contract (ZoraV4CoinHook) that handles pool lifecycle events like swaps and automatic reward distribution.

### Swap Path for Multi-Hop Rewards

#### getPayoutSwapPath

```solidity
function getPayoutSwapPath(IDeployedCoinVersionLookup coinVersionLookup) external view returns (PayoutSwapPath memory);
```

Returns the swap path configuration for converting this coin's fees to its final payout currency. This enables multi-hop swaps through intermediate currencies.

The `PayoutSwapPath` struct contains:
- `currencyIn`: The input currency (this coin)
- `path`: Array of swap steps to reach the final payout currency

Example for a content coin paired with a backing coin:
1. Content coin → Backing coin (first hop)
2. Backing coin → USDC (second hop)

### Coin Trades

#### burn

```solidity
function burn(uint256 amount) external;
```

Allows users to burn their own tokens, permanently removing them from circulation.

### Management Functions

#### setContractURI

```solidity
function setContractURI(string memory newURI) external onlyOwner;
```

Updates the coin's metadata URI. This can only be called by an owner of the coin.

#### setPayoutRecipient

```solidity
function setPayoutRecipient(address newPayoutRecipient) external onlyOwner;
```

Updates the address that receives creator rewards. This can only be called by an owner of the coin.

### Query Functions

```solidity
function tokenURI() external view returns (string memory);
function platformReferrer() external view returns (address);
function currency() external view returns (address);
```

These functions provide access to key coin information:
- `tokenURI`: Returns the coin's metadata URI
- `platformReferrer`: Returns the address of the platform referrer who earns fees from trades
- `currency`: Returns the address of the backing currency this coin is paired with

## Events

### Hook Events

#### Swapped

```solidity
event Swapped(
    address indexed sender,
    address indexed swapSender,
    bool isTrustedSwapSenderAddress,
    PoolKey key,
    bytes32 indexed poolKeyHash,
    SwapParams params,
    int128 amount0,
    int128 amount1,
    bool isCoinBuy,
    bytes hookData,
    uint160 sqrtPriceX96
);
```

Emitted by the hook when a swap occurs, providing detailed information about the transaction including price data and swap direction.

#### CoinMarketRewardsV4

```solidity
event CoinMarketRewardsV4(
    address indexed coin,
    address indexed currency,
    address indexed payoutRecipient,
    address platformReferrer,
    address tradeReferrer,
    address protocolRewardRecipient,
    address dopplerRecipient,
    MarketRewardsV4 marketRewards
);
```

Emitted when market rewards are distributed, showing exactly how much each recipient received in the backing currency.

### Coin Events

#### CoinBuy

```solidity
event CoinBuy(
    address indexed buyer,
    address indexed recipient,
    address indexed tradeReferrer,
    uint256 coinsPurchased,
    address currency,
    uint256 amountFee,
    uint256 amountSold
);
```

Emitted when coins are purchased, tracking the buyer, recipient, trade referrer, amount of coins purchased, currency used, fees paid, and total amount spent.

#### CoinSell

```solidity
event CoinSell(
    address indexed seller,
    address indexed recipient,
    address indexed tradeReferrer,
    uint256 coinsSold,
    address currency,
    uint256 amountFee,
    uint256 amountPurchased
);
```

Emitted when coins are sold, tracking the seller, recipient, trade referrer, amount of coins sold, currency received, fees paid, and total amount received.

#### CoinTransfer

```solidity
event CoinTransfer(
    address indexed sender,
    address indexed recipient,
    uint256 amount,
    uint256 senderBalance,
    uint256 recipientBalance
);
```

Emitted on any token transfer, providing detailed information about the transfer including updated balances.

#### ContractMetadataUpdated

```solidity
event ContractMetadataUpdated(
    address indexed caller,
    string newURI,
    string name
);
```

Emitted when the contract metadata URI is updated.

#### CoinPayoutRecipientUpdated

```solidity
event CoinPayoutRecipientUpdated(
    address indexed caller,
    address indexed prevRecipient,
    address indexed newRecipient
);
```

Emitted when the payout recipient is updated.

#### ContractURIUpdated

```solidity
event ContractURIUpdated();
```

Emitted when the contract URI is updated, used for standards compliance with ERC7572.

#### CoinTradeRewards

```solidity
event CoinTradeRewards(
    address indexed payoutRecipient,
    address indexed platformReferrer,
    address indexed tradeReferrer,
    address protocolRewardRecipient,
    uint256 creatorReward,
    uint256 platformReferrerReward,
    uint256 traderReferrerReward,
    uint256 protocolReward,
    address currency
);
```

Emitted when trade rewards are distributed, showing the breakdown of rewards to each recipient.

## Error Handling

The contract defines several custom errors that provide specific information about failed operations:

### Common Errors

- `AddressZero`: Operation attempted with a zero address
- `InsufficientFunds`: Insufficient funds for the operation
- `InsufficientLiquidity`: Insufficient liquidity for a transaction
- `SlippageBoundsExceeded`: Slippage bounds exceeded during a transaction
- `InitialOrderSizeTooLarge`: Initial order size too large
- `EthAmountMismatch`: ETH value doesn't match the currency amount
- `EthAmountTooSmall`: ETH amount too small for the transaction
- `ERC20TransferAmountMismatch`: Unexpected ERC20 transfer amount
- `EthTransferInvalid`: Invalid ETH transfer
- `EthTransferFailed`: ETH transfer failed
- `OnlyPool`: Operation attempted by an entity other than the pool
- `OnlyWeth`: Operation attempted by an entity other than WETH
- `MarketNotGraduated`: Market is not yet graduated
- `MarketAlreadyGraduated`: Market is already graduated
- `InvalidCurrencyLowerTick`: Lower tick is not less than maximum or not a multiple of 200
- `InvalidWethLowerTick`: Lower tick is not set to the default value
- `LegacyPoolMustHaveOneDiscoveryPosition`: Legacy pool does not have one discovery position
- `DopplerPoolMustHaveMoreThan2DiscoveryPositions`: Doppler pool doesn't have enough discovery positions
- `InvalidPoolVersion`: Invalid pool version specified

### Hook-Specific Errors

- `NotACoin`: Non-coin contract attempted to use V4 hook
- `NoCoinForHook`: Pool not properly initialized for hook
- `PathMustHaveAtLeastOneStep`: Invalid swap path configuration for multi-hop rewards
- `CoinVersionLookupCannotBeZeroAddress`: Version lookup contract cannot be zero address
