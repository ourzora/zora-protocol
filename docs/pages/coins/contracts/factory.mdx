# `ZoraFactory.sol`

The `ZoraFactory` contract is an upgradeable contract which is the canonical factory for coins.

The contract is upgradable by the Zora team to update coin features, but any deployed coins are immutable and cannot be updated.

## Overview

The `ZoraFactory` implements the `IZoraFactory` interface and serves as the entry point for creating new coins in the ZORA Coins Protocol. It handles the deployment of both V3 (Uniswap V3) and V4 (Uniswap V4) coin contracts, their associated pools, and the initial setup of liquidity.

The factory automatically determines whether to deploy a V3 or V4 coin based on the pool configuration provided.

## Canonical Deployment Address

| Chain       | Chain ID | Contract Name | Address                                                                 |
|-------------|----------|---------------|-------------------------------------------------------------------------|
| Base        | 8453     | `ZoraFactory` | [0x777777751622c0d3258f214F9DF38E35BF45baF3](https://basescan.org/address/0x777777751622c0d3258f214F9DF38E35BF45baF3) |
| Base Sepolia| 84532    | `ZoraFactory` | [0x777777751622c0d3258f214F9DF38E35BF45baF3](https://sepolia.basescan.org/address/0x777777751622c0d3258f214F9DF38E35BF45baF3) |


### Key Methods

#### deploy (Current Recommended Method)

```solidity
function deploy(
    address payoutRecipient,
    address[] memory owners,
    string memory uri,
    string memory name,
    string memory symbol,
    bytes memory poolConfig,
    address platformReferrer,
    address postDeployHook,
    bytes calldata postDeployHookData,
    bytes32 coinSalt
) external payable returns (address coin, bytes memory postDeployHookDataOut);
```

This is the current recommended function for creating a new coin contract with the specified parameters and its associated Uniswap pool.

Parameters:
- `payoutRecipient`: The recipient of creator reward payouts; this can be updated by any owner later on
- `owners`: An array of addresses that will have permission to manage the coin's payout address and metadata URI
- `uri`: The coin metadata URI (should be an IPFS URI)
- `name`: The name of the coin (e.g., "horse galloping")
- `symbol`: The trading symbol for the coin (e.g., "HORSE")
- `poolConfig`: Encoded pool configuration that determines V3 vs V4 deployment and pool parameters
- `platformReferrer`: The address that will receive platform referral rewards from trades
- `postDeployHook`: Address of a contract implementing the `IHasAfterCoinDeploy` interface that runs after deployment
- `postDeployHookData`: Custom data to be passed to the post-deployment hook
- `coinSalt`: Salt for deterministic deployment, enables predictable coin addresses

Returns:
- The address of the deployed coin contract
- Any data returned from the post-deployment hook

#### coinAddress

```solidity
function coinAddress(
    address msgSender,
    string memory name,
    string memory symbol,
    bytes memory poolConfig,
    address platformReferrer,
    bytes32 coinSalt
) external view returns (address);
```

This function allows you to predict the address of a coin contract before it's deployed. Useful for preparing integrations.

Parameters:
- `msgSender`: The address that will call the deploy function
- `name`: The name of the coin
- `symbol`: The symbol of the coin
- `poolConfig`: The pool configuration
- `platformReferrer`: The platform referrer address
- `coinSalt`: The salt to be used for deployment

Returns:
- The address where the coin will be deployed

#### Deprecated Deploy Functions

The factory also contains several deprecated deployment functions that are maintained for backward compatibility:

```solidity
// Deprecated: Use the recommended deploy function instead
function deploy(
    address payoutRecipient,
    address[] memory owners,
    string memory uri,
    string memory name,
    string memory symbol,
    bytes memory poolConfig,
    address platformReferrer,
    uint256 orderSize
) external payable returns (address, uint256);

// Deprecated: Use the recommended deploy function instead
function deployWithHook(
    address payoutRecipient,
    address[] memory owners,
    string memory uri,
    string memory name,
    string memory symbol,
    bytes memory poolConfig,
    address platformReferrer,
    address hook,
    bytes calldata hookData
) external payable returns (address coin, bytes memory hookDataOut);
```

These older functions don't use deterministic deployment, meaning you can't predict coin addresses before deployment. The current recommended `deploy` function supports deterministic addresses and post-deployment hooks in a single operation.

#### Pool Configuration

The `poolConfig` parameter is a bytes-encoded configuration that determines:
- **Version**: Whether to deploy V3 or V4 coin
- **Currency**: The trading pair currency (can be address(0) for ETH/WETH)
- **Pool Parameters**: Fee tier, tick spacing, and other pool-specific settings

For V4 coins, additional parameters include:
- **Hook Configuration**: Advanced pool behavior settings
- **Multi-Position Setup**: Support for complex liquidity curves
- **Reward Routing**: Multi-hop swap path configuration

Notes:
- When creating a coin with ETH/WETH, you must send ETH with the transaction equal to the `orderSize` parameter
- For other currencies, the factory will pull the specified amount from your wallet (requires approval)
- V4 coins support more advanced features like multi-hop reward distribution

### Events

#### CoinCreated (V3)

```solidity
event CoinCreated(
    address indexed caller,
    address indexed payoutRecipient,
    address indexed platformReferrer,
    address currency,
    string uri,
    string name,
    string symbol,
    address coin,
    address pool,
    string version
);
```

Emitted when a new V3 coin is created through the factory.

Event Parameters:
- `caller`: The address that called the deploy function
- `payoutRecipient`: The address of the creator payout recipient
- `platformReferrer`: The address of the platform referrer
- `currency`: The address of the trading currency
- `uri`: The metadata URI of the coin
- `name`: The name of the coin
- `symbol`: The symbol of the coin
- `coin`: The address of the newly created coin contract
- `pool`: The address of the associated Uniswap V3 pool
- `version`: The version string of the coin implementation

#### CoinCreatedV4 (V4)

```solidity
event CoinCreatedV4(
    address indexed caller,
    address indexed payoutRecipient,
    address indexed platformReferrer,
    address currency,
    string uri,
    string name,
    string symbol,
    address coin,
    PoolKey poolKey,
    bytes32 poolKeyHash,
    string version
);
```

Emitted when a new V4 coin is created through the factory.

Event Parameters:
- `caller`: The address that called the deploy function
- `payoutRecipient`: The address of the creator payout recipient
- `platformReferrer`: The address of the platform referrer
- `currency`: The address of the trading currency
- `uri`: The metadata URI of the coin
- `name`: The name of the coin
- `symbol`: The symbol of the coin
- `coin`: The address of the newly created coin contract
- `poolKey`: The Uniswap V4 pool key struct
- `poolKeyHash`: Hash of the pool key for efficient indexing
- `version`: The version string of the coin implementation

### Error Handling

The factory defines custom errors to provide specific information about failed operations:

- `ERC20TransferAmountMismatch`: The amount of ERC20 tokens transferred does not match the expected amount
- `EthTransferInvalid`: ETH is sent with a transaction but the currency is not WETH

## Usage with SDK

While you can interact directly with the factory contract, it's recommended to use the Zora Coins SDK which handles the complexities of coin creation and automatically selects the appropriate version:

```typescript
import { createCoin } from "@zoralabs/coins-sdk";
import { createWalletClient, createPublicClient, http } from "viem";
import { base } from "viem/chains";
import { Address, Hex, parseEther } from "viem";

// Set up viem clients
const publicClient = createPublicClient({
  chain: base,
  transport: http("<RPC_URL>"),
});

const walletClient = createWalletClient({
  account: "0x<YOUR_ACCOUNT>" as Hex,
  chain: base,
  transport: http("<RPC_URL>"),
});

// Define coin parameters
const coinParams = {
  name: "My Awesome Coin",
  symbol: "MAC",
  uri: "ipfs://bafkreihz5knnvvsvmaxlpw3kout23te6yboquyvvs72wzfulgrkwj7r7dm",
  payoutRecipient: "0xYourAddress" as Address,
  platformReferrer: "0xYourPlatformReferrerAddress" as Address, // Optional
  initialPurchaseWei: parseEther("0.1"), // Optional: Initial amount to purchase in Wei
  // The SDK will automatically select V4 for new coins unless specified otherwise
  version: "v4", // Optional: Force specific version
};

// Create the coin
const result = await createCoin(coinParams, walletClient, publicClient);
console.log("Coin address:", result.address);
console.log("Coin version:", result.version); // "v3" or "v4"
```

## Version Selection

The factory automatically determines which version to deploy based on several factors:

1. **Pool Configuration**: V4-specific configurations will deploy V4 coins
2. **Currency Type**: Certain currency configurations may prefer specific versions
3. **Feature Requirements**: Advanced features like multi-hop rewards require V4

### V3 vs V4 Feature Comparison

| Feature | V3 | V4 |
|---------|----|----|
| Basic Trading | ✅ | ✅ |
| ERC20 Functionality | ✅ | ✅ |
| Simple Reward Distribution | ✅ | ✅ |
| Multi-Hop Reward Swapping | ❌ | ✅ |
| Advanced Hook System | ❌ | ✅ |
| Complex Liquidity Curves | ❌ | ✅ |
| Gas Efficiency | Good | Better |
| Pool Customization | Limited | Extensive |

## Advanced Configuration

### Currency Options

When creating a coin, you have multiple options for the trading currency:

1. **ETH/WETH**: Use `address(0)` for the currency parameter. This is the most common option, allowing users to buy and sell coins with ETH.

2. **ERC20 Token**: Specify the address of an ERC20 token. This creates a coin that trades against that specific token.

3. **Other Coins (V4 Only)**: V4 coins can be paired with other coins, enabling complex reward distribution chains.

### Initial Purchase

The `orderSize` parameter (or `initialPurchaseWei` in the SDK) determines the initial purchase amount when creating a coin:

- Setting this to a non-zero value creates initial liquidity in the pool
- For ETH/WETH coins, this amount must be sent with the transaction
- For ERC20 coins, the factory must be approved to spend this amount

### V4-Specific Configuration

V4 coins support additional configuration options:

- **Multi-Position Liquidity**: Automatically create multiple liquidity positions for better price discovery
- **Custom Hook Logic**: Advanced pool behavior and fee collection
- **Swap Path Optimization**: Intelligent routing for multi-hop reward distribution

## Security Considerations

- The factory is the only contract allowed to create official ZORA protocol coins
- Platform referrer addresses are permanently set at creation and cannot be changed
- Owner addresses have some control over the coin (metadata, payout recipient)
- V3 coins are processed through Uniswap V3 pools, subject to their slippage and price impact mechanics
- V4 coins benefit from improved hooks and better MEV protection
- All coin versions maintain the same security guarantees for immutability after deployment

