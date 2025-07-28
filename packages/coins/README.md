# Coins

A protocol for creating and trading creator and content coins with automatic rewards distribution on top of Uniswap V4 hooks.

## Architecture Overview

The Coins protocol consists of several key contracts that work together to enable coin creation, trading, and customization:

### Core Contracts

#### BaseCoin

The abstract base contract that provides core ERC20 functionality with additional features:

- **ERC20 with Permit**: Standard token functionality with gasless approvals
- **Multi-ownership**: Support for multiple owners
- **Reward Distribution**: Distributes rewards on swaps
- **Comment System**: Support for on-chain comments via `ICoinComments`

#### ContentCoin

Content coin implementation that inherits from `BaseCoin`:

- **Creator Coin Backing**: Always uses the creator's CreatorCoin as the backing currency
- **Supply**: 1 billion total supply (990M for liquidity pool, 10M creator reward)
- **Multiple per Creator**: Each creator can have multiple content coins

#### CreatorCoin

Specialized coin implementation for creators (one per creator) that inherits from `BaseCoin`:

- **Vesting Schedule**: Built-in token vesting for creator rewards (5-year vesting)
- **Fixed Currency**: Always uses ZORA token as backing currency
  - **Address**: `0x1111111111166b7FE7bd91427724B487980aFc69`
  - **Network**: Base mainnet only (protocol is deployed exclusively on Base)
- **Supply**: 1 billion total supply (500M for market, 500M for creator vesting)
- **Single per Creator**: Each creator has exactly one CreatorCoin that backs their content coins

#### Coin (V3 Implementation - Legacy)

The V3 implementation of coins using Uniswap V3 integration, predating the V4 architecture:

- **Uniswap V3 Integration**: Uses Uniswap V3 factory and swap router for trading
- **Concentrated Liquidity**: Manages multiple liquidity positions with custom ranges
- **Currency Flexibility**: Supports any ERC20 token as backing currency (not restricted to ZORA)
- **Position Management**: Maintains array of `LpPosition` structs for liquidity tracking
- **Market Rewards**: Distributes rewards from liquidity position fees
- **V3 vs V4 Differences**: 
  - V3 uses traditional swap router patterns vs V4's singleton pool manager
  - V3 requires separate pool deployment vs V4's integrated pool creation
  - V3 has manual liquidity position management vs V4's hook-based automation
- **Migration Path**: Existing V3 coins continue to operate but new deployments use V4

#### ZoraFactory (Proxy Contract)

The proxy contract that delegates to ZoraFactoryImpl using the ERC1967 proxy pattern:

- **ERC1967 Proxy**: Standard upgradeable proxy implementation from OpenZeppelin
- **Immutable Name**: Distinguished by immutable name field (`keccak256("ZoraFactory")`) for verification
- **Delegation Pattern**: All function calls are delegated to the implementation contract
- **Upgrade Safety**: Supports safe upgrades through the UUPS pattern in the implementation
- **Cross-Chain Consistency**: Deterministic deployment ensures same address across chains
- **Critical Initialization**: Must be initialized in the same transaction as deployment
  - Proxy deployment and initialization are separate steps for address mining
  - Failure to initialize leaves the factory in an unusable state
- **Verification**: Unique bytecode allows proper contract verification on block explorers

#### ZoraFactoryImpl

The main factory contract for deploying coins:

- **Deterministic Deployment**: Uses CREATE2 for predictable addresses when deploying coins
- **Version Management**: Supports multiple coin implementations
- **Hook Integration**: Automated hook deployment and configuration
- **Upgrade Support**: UUPS upgradeable pattern for factory improvements and bug fixes

#### HookUpgradeGate

Manages safe upgrade paths for V4 coin hooks with strict security controls:

- **Upgrade Path Registry**: Maintains `mapping(address => mapping(address => bool))` of allowed upgrades
- **Multi-Path Registration**: Single upgrade can be registered for multiple base implementations
- **Owner Control**: Uses Ownable2Step for secure ownership transfers with two-step process
- **Security Features**:
  - Only owner can register or remove upgrade paths
  - Prevents unauthorized hook upgrades that could compromise coins
  - Whitelist approach ensures only vetted upgrades are allowed
- **Upgrade Process**:
  1. Owner registers upgrade path via `registerUpgradePath()`
  2. Coin creators can then upgrade their hooks using registered paths
  3. Upgrades can be revoked by owner via `removeUpgradePath()`
- **Event Logging**: Emits `UpgradeRegistered` and `UpgradeRemoved` events for transparency
- **Use Cases**: Enables safe migration of coins to new hook implementations without breaking existing functionality

### Hook System

The protocol supports various hooks for customizing coin behavior:

#### BaseZoraV4CoinHook

Immutable base hook contract providing behavior that happens after swaps:

- **Deployment Hooks**: Integrates with coin deployment process for initialization
- **Trading Hooks**: Hooks into swap events for custom logic execution
- **Reward Distribution**: Manages reward distribution during trading activities
- **State Management**: Maintains hook-specific state across transactions
- **Content Validation**: Ensures proper coin -> liquidity association
- **Liquidity Migration**: Supports controlled liquidity migration by the creator to a new hook.

## Supply Distribution Summary

| Coin Type       | Total Supply  | Liquidity Pool | Creator Allocation | Vesting Period |
| --------------- | ------------- | -------------- | ------------------ | -------------- |
| **ContentCoin** | 1,000,000,000 | 990,000,000    | 10,000,000         | None           |
| **CreatorCoin** | 1,000,000,000 | 500,000,000    | 500,000,000        | 5 years        |

_All amounts are in tokens with 18 decimals_

## Deployment

The `ZoraFactory` contract is deployed deterministically using a turnkey account. The deployment process uses a helper contract, [DeterministicDeployerAndCaller](../../packages/shared-contracts/src/deployment/DeterministicDeployerAndCaller.sol).

### Prerequisites

- Ensure you have [Forge](https://book.getfoundry.sh/getting-started/installation) installed.
- Familiarity with [turnkey accounts](https://docs.turnkey.com/) is recommended.

### Setting up environment variables

In the `packages/coins` directory:

1. Copy `.env.example` to `.env`
2. Populate the parameters in `.env`

### Deploying the Coins Factory

1. Deploy the `ZoraFactory` contract, you must pass the `--ffi` flag to enable calling an external script to sign the deployment with turnkey:

```bash
forge script script/Deploy.s.sol $(chains {chainName} --deploy) --broadcast --verify --ffi
```

where `{chainName}` is the emdash name of the chain you want to deploy on.

2. Verify the factory contract. Since it is deployed with create2, foundry won't always recognize the deployed contract; verification instructions will be printed out in the logs.
