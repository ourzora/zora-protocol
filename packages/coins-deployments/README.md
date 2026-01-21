# Coins Deployments

Centralized deployment scripts and utilities for the Zora Coins protocol.

## Overview

This package contains all deployment scripts, configuration, and utilities for deploying Zora Coins contracts across different networks. It provides:

- **Deterministic CREATE2 deployments** for predictable contract addresses
- **Two-step deployment process** for limit order contracts
- **Tenderly testnet deployment** support with automated funding
- **Base deployment utilities** for reading/writing deployment state

## Package Structure

```
coins-deployments/
├── src/
│   └── deployment/
│       └── CoinsDeployerBase.sol           # Base contract with deployment utilities
├── script/
│   ├── DeployAllContracts.s.sol            # Main atomic deployment script
│   ├── DeployLimitOrders.s.sol             # Deploy limit orders only (legacy)
│   ├── DeployHookRegistry.s.sol            # Deploy hook registry only
│   └── DeployTrustedMsgSenderLookup.s.sol  # Deploy msg sender lookup only
├── scripts/
│   ├── deploy-to-tenderly.sh               # Tenderly deployment automation
│   └── verify-contracts.ts                 # Batch contract verification script
├── addresses/
│   ├── {chainId}.json                      # Production deployment addresses
│   └── {chainId}_dev.json                  # Development deployment addresses
└── .env.example                             # Environment variable template
```

## Deployment Scripts

### DeployAllContracts.s.sol

**Purpose**: Atomically deploys all Zora Coins contracts in the correct order to avoid circular dependencies.

**Usage**:

```bash
# Production deployment
forge script script/DeployAllContracts.s.sol \
  --rpc-url <RPC_URL> \
  --private-key <PRIVATE_KEY> \
  --broadcast \
  --verify

# Development deployment on Base
DEV=true forge script script/DeployAllContracts.s.sol \
  --rpc-url <BASE_RPC_URL> \
  --private-key <PRIVATE_KEY> \
  --broadcast
```

**What it does**:

This script deploys all contracts in a single atomic transaction batch:

1. **Factory Proxy**: Deploys ProxyShim and ZoraFactory proxy (without implementation)
2. **Hook Registry**: Deploys ZoraHookRegistry using CREATE2
3. **Order Book Authority**: Deploys AccessManager for limit order book
4. **Limit Order Book**: Deploys ZoraLimitOrderBook using CREATE2
5. **Swap Router**: Deploys SwapWithLimitOrders router using CREATE2
6. **Trusted Msg Sender Lookup**: Deploys TrustedMsgSenderProviderLookup
7. **Upgrade Gate**: Deploys HookUpgradeGate
8. **Coin Implementations**: Deploys ContentCoin and CreatorCoin implementations
9. **Content Coin Hook**: Deploys the V4 coin hook (now has all dependencies)
10. **Factory Implementation**: Deploys ZoraFactoryImpl
11. **Upgrade Factory**: Upgrades factory proxy to implementation and initializes

**Key Benefits**:

- ✅ **Atomic deployment**: All contracts deployed in one script execution
- ✅ **Correct dependency order**: Factory proxy → LOB → Hook → Factory impl
- ✅ **No circular dependencies**: Breaks the circular dependency by deploying factory proxy first
- ✅ **Single source of truth**: All deployment logic in one place
- ✅ **Automatic state management**: Saves deployment addresses only if all steps succeed

## Tenderly Deployment

The `scripts/deploy-to-tenderly.sh` script automates the entire deployment process for Tenderly virtual testnets.

### Setup

1. Copy `.env.example` to `.env`:

   ```bash
   cp .env.example .env
   ```

2. Fill in the required values:
   ```bash
   TENDERLY_ACCOUNT=your-account
   TENDERLY_PROJECT=your-project
   TENDERLY_ACCESS_KEY=your-access-key
   TENDERLY_DEPLOYER_PRIVATE_KEY=your-private-key
   TESTNET_ID=your-testnet-id
   TENDERLY_VIRTUAL_TESTNET_RPC_URL=https://virtual.base.rpc.tenderly.co/your-testnet-id
   ```

### Running the Deployment

```bash
bash scripts/deploy-to-tenderly.sh
```

### What it does

The script automates the complete deployment flow:

1. **Fund Deployer**: Automatically funds the deployer account with 1 ETH
2. **Step 1**: Compute deterministic addresses (no broadcasting)
3. **Step 2**: Deploy TrustedMsgSenderProviderLookup
4. **Step 3**: (Optional) Upgrade coin implementation
5. **Step 4**: Deploy Limit Order Book contracts

All deployments include contract verification on Tenderly.

### Helper Functions

The script includes reusable functions:

#### `fund_account(private_key, [amount])`

Funds an account on Tenderly testnet using the `tenderly_setBalance` RPC method.

- `private_key`: The private key of the account to fund
- `amount`: Optional hex amount in wei (defaults to 1 ETH: `0xDE0B6B3A7640000`)

#### `run_script(script_name, broadcast)`

Runs a forge script with optional broadcasting and verification.

- `script_name`: Path to the script file
- `broadcast`: `true` to deploy with verification, `false` for dry-run

## Contract Verification

The `scripts/verify-contracts.ts` script automates contract verification on block explorers (Etherscan, Basescan, etc.) after deployment.

### Usage

```bash
cd packages/coins-deployments
npx tsx scripts/verify-contracts.ts <script_name> <chain>
```

**Arguments:**

- `script_name`: The Forge script filename (e.g., `UpgradeCoinImpl.sol`, `DeployAllContracts.s.sol`)
- `chain`: The chain name from viem/chains (e.g., `base`, `mainnet`, `sepolia`, `baseSepolia`, `zora`, `zoraSepolia`)

### Examples

```bash
# Verify contracts from UpgradeCoinImpl deployment on Base
npx tsx scripts/verify-contracts.ts UpgradeCoinImpl.sol base

# Verify contracts from full deployment on mainnet
npx tsx scripts/verify-contracts.ts DeployAllContracts.s.sol mainnet
```

### How It Works

1. Reads the Forge broadcast file at `broadcast/<script>/<chainId>/run-latest.json`
2. Filters for `CREATE` transactions (deployed contracts)
3. Runs `forge verify-contract` with `--guess-constructor-args` for each contract
4. Reports success/failure for each verification

### Prerequisites

- The `chains` CLI tool must be installed and configured with API keys
- Contracts must have been deployed (broadcast file must exist)
- May need to retry if rate limited by the block explorer API

### Rate Limiting

Block explorer APIs may rate limit verification requests. If verification fails with a rate limit error, wait a moment and run the script again. Already-verified contracts will be skipped automatically.

## Development Deployments

The package supports separate development deployments on Base using the `DEV` environment variable. When `DEV=true`, the deployment scripts use separate deployment files (`addresses/8453_dev.json`) and chain configs (`chainConfigs/8453_dev.json`).

### Quick Start

```bash
# Development deployment on Base (single atomic script)
DEV=true forge script script/DeployAllContracts.s.sol \
  --rpc-url $BASE_RPC \
  --private-key $PRIVATE_KEY \
  --broadcast

# Test without broadcasting first
DEV=true forge script script/DeployAllContracts.s.sol --rpc-url $BASE_RPC
```

The DEV flag causes the script to:

- Use `addresses/8453_dev.json` instead of `addresses/8453.json`
- Use `chainConfigs/8453_dev.json` for network configuration
- Deploy all contracts atomically in the correct dependency order

## Base Deployment Contract

### CoinsDeployerBase.sol

Base contract providing deployment utilities and state management.

**Key Features**:

- **Deployment State Management**: Read/write deployment addresses to JSON files
- **CREATE2 Deterministic Deployment**: Compute and deploy contracts with predictable addresses
- **Hardcoded Salts**: Uses specific salts for deterministic address generation
- **Network Configuration**: Helper functions for retrieving network-specific addresses

**Main Functions**:

- `readDeployment()`: Read deployment state from `addresses/{chainId}.json`
- `saveDeployment()`: Save deployment state to JSON
- `computeProxyShimAddress()`: Compute CREATE2 address for ProxyShim
- `computeFactoryAddress()`: Compute CREATE2 address for ZoraFactory
- `computeAuthorityAddress()`: Compute CREATE2 address for OrderBookAuthority
- `computeLimitOrderBookAddress()`: Compute CREATE2 address for ZoraLimitOrderBook
- `computeSwapRouterAddress()`: Compute CREATE2 address for Zora Router
- `deployProxyShimDeterministic()`: Deploy proxy shim with CREATE2
- `deployFactoryDeterministic()`: Deploy factory with CREATE2
- `deployOrderBookAuthorityDeterministic()`: Deploy authority with CREATE2
- `deployLimitOrderBookDeterministic()`: Deploy limit order book with CREATE2
- `deploySwapRouterDeterministic()`: Deploy router with CREATE2

**Hardcoded Salts**:

The first 20 bytes are zeros to allow any address to deploy:

- Proxy Shim: `0x0000000000000000000000000000000000000000000000000000000000000000`
- Authority: `0x0000000000000000000000000000000000000000000000000000000000000001`
- Limit Order Book: `0x0000000000000000000000000000000000000000000000000000000000000002`
- Swap Router: `0x0000000000000000000000000000000000000000000000000000000000000003`
- Factory: `0x0000000000000000000000000000000000000000000000000000000000000004`

## Deployment State

Deployment addresses are stored in `addresses/{chainId}.json` with the following structure:

```json
{
  "ZORA_FACTORY": "0x...",
  "ZORA_HOOK_REGISTRY": "0x...",
  "ORDER_BOOK_AUTHORITY": "0x...",
  "ZORA_LIMIT_ORDER_BOOK": "0x...",
  "ZORA_ROUTER": "0x...",
  "TRUSTED_MSG_SENDER_LOOKUP": "0x..."
}
```

## Deployment Architecture

The atomic deployment approach resolves circular dependencies by deploying contracts in the correct order:

### Dependency Resolution

The deployment handles these key dependencies:

1. **Factory → Hook**: Hook needs factory address in constructor

   - **Solution**: Deploy factory proxy first (gets address), deploy hook later

2. **Limit Order Book → Factory**: LOB needs factory address

   - **Solution**: LOB deployed after factory proxy

3. **Hook → Limit Order Book**: Hook needs LOB address

   - **Solution**: LOB deployed before hook

4. **Factory Implementation → Hook**: Factory impl needs hook address
   - **Solution**: Hook deployed before factory impl

### Deployment Order

```
1. Factory Proxy (no impl) → Gets address A
2. Hook Registry
3. Order Book Authority
4. Limit Order Book (uses address A)
5. Swap Router
6. Trusted Msg Sender Lookup
7. Upgrade Gate
8. Coin Implementations
9. Hook (uses LOB address)
10. Factory Implementation (uses hook address)
11. Upgrade factory proxy to impl
```

This order ensures all dependencies are available when needed.

## Development

### Testing Locally

Run the deployment script in dry-run mode (no broadcasting) to simulate the deployment:

```bash
# Simulate deployment
forge script script/DeployAllContracts.s.sol \
  --rpc-url http://localhost:8545

# For DEV deployments
DEV=true forge script script/DeployAllContracts.s.sol \
  --rpc-url http://localhost:8545
```

### Adding New Networks

1. Add chain configuration to `chainConfigs/{chainId}.json` with required addresses:
   - `PROXY_ADMIN`
   - `UNISWAP_V4_POOL_MANAGER`
   - `UNISWAP_SWAP_ROUTER`
   - Other Uniswap and protocol addresses
2. Run the deployment script:
   ```bash
   forge script script/DeployAllContracts.s.sol \
     --rpc-url <NETWORK_RPC> \
     --private-key $PRIVATE_KEY \
     --broadcast --verify
   ```
3. Addresses will be saved to `addresses/{chainId}.json`

## Security Considerations

- **Private Keys**: Never commit `.env` files or expose private keys
- **CREATE2 Salts**: Hardcoded salts ensure deterministic addresses but prevent redeployment with same params
- **Address Verification**: Always verify deployed addresses match expected addresses
- **Proxy Admin**: OrderBookAuthority deployment requires a proxy admin address

## Troubleshooting

### Deployment failures

If the deployment script fails midway:

- The script is atomic - if any step fails, the entire deployment is reverted
- Check the error message to identify which step failed
- Common issues:
  - Insufficient gas or funds
  - Network connectivity issues
  - Contract already deployed (check addresses file)

### "No code at address" errors

- Ensure chain configuration file exists: `chainConfigs/{chainId}.json` or `chainConfigs/{chainId}_dev.json`
- Verify all required addresses in chain config have deployed contracts
- For DEV deployments, ensure `PROXY_ADMIN` is deployed on the network

### Verification failures

- Check that API key is correct for the block explorer
- Verify verifier URL format matches the network
- For Tenderly: `{TENDERLY_VIRTUAL_TESTNET_RPC_URL}/verify/etherscan`
- Contract may still be deployed even if verification fails

### "Insufficient funds" errors

- Ensure deployer account has sufficient native token
- For Tenderly: Script automatically funds deployer with 1 ETH
- For mainnet/testnet: Fund deployer account before running
