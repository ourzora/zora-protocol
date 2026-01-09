# Development Deployments on Base

## Overview

The coins-deployments package supports separate development deployments on Base mainnet using the `DEV` environment variable. This allows testing contract changes in a production-like environment without affecting production deployments.

## Key Features

- ✅ **Separate deployment files**: `addresses/8453_dev.json` vs `addresses/8453.json`
- ✅ **Separate chain configs**: `chainConfigs/8453_dev.json` vs `chainConfigs/8453.json`
- ✅ **Atomic deployment**: Single script deploys all contracts in correct order
- ✅ **No circular dependencies**: Factory proxy → LOB → Hook → Factory impl
- ✅ **Environment-based**: Controlled by `DEV=true` environment variable

## Quick Start

### Test Deployment (Simulation)

First, test the deployment without broadcasting:

```bash
DEV=true forge script script/DeployAllContracts.s.sol \
  --rpc-url $BASE_RPC
```

This simulates the deployment and shows:

- All contract addresses that will be deployed
- Estimated gas costs
- Any potential errors

### Broadcast Deployment

Once the simulation succeeds, broadcast the actual deployment:

```bash
DEV=true forge script script/DeployAllContracts.s.sol \
  --rpc-url $BASE_RPC \
  --private-key $PRIVATE_KEY \
  --broadcast
```

Add `--verify` to verify contracts on Basescan:

```bash
DEV=true forge script script/DeployAllContracts.s.sol \
  --rpc-url $BASE_RPC \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify
```

## Deployment Process

The atomic deployment script (`DeployAllContracts.s.sol`) handles all steps in a single execution:

### 1. Factory Proxy

Deploys ProxyShim and ZoraFactory proxy (without implementation):

- Uses regular CREATE (not CREATE2)
- Gets a new address each deployment
- This address is used by all subsequent contracts

### 2. Hook Registry

Deploys ZoraHookRegistry using CREATE2:

- Deterministic address across deployments
- Initial owner is PROXY_ADMIN from chain config

### 3. Order Book Authority

Deploys AccessManager for limit order book permissions:

- Deterministic address using CREATE2
- Owner is PROXY_ADMIN

### 4. Limit Order Book

Deploys ZoraLimitOrderBook using CREATE2:

- Needs factory address (from step 1)
- Needs hook registry address (from step 2)
- Deterministic address

### 5. Swap Router

Deploys SwapWithLimitOrders using CREATE2:

- Needs limit order book address (from step 4)
- Deterministic address

### 6. Trusted Message Sender Lookup

Deploys TrustedMsgSenderProviderLookup:

- Needs router address (from step 5)
- Configures trusted senders:
  - Uniswap Universal Router
  - Uniswap V4 Position Manager
  - Zora Router (from step 5)

### 7. Upgrade Gate

Deploys HookUpgradeGate:

- Owner is PROXY_ADMIN

### 8. Coin Implementations

Deploys ContentCoin and CreatorCoin implementations:

- Uses PoolManager, ProtocolRewards, and Doppler Airlock from chain config

### 9. Content Coin Hook

Deploys the V4 coin hook:

- Needs factory address (from step 1)
- Needs limit order book address (from step 4)
- Needs trusted message sender lookup (from step 6)
- Needs upgrade gate (from step 7)
- Uses deterministic salt for hook address requirements

### 10. Factory Implementation

Deploys ZoraFactoryImpl:

- Needs coin implementations (from step 8)
- Needs hook address (from step 9)
- Needs hook registry (from step 2)

### 11. Upgrade Factory Proxy

Upgrades the factory proxy to the real implementation:

- Calls `upgradeToAndCall` on the proxy
- Initializes factory with PROXY_ADMIN as owner

## File Structure

### Development Deployment File

Located at `addresses/8453_dev.json`:

```json
{
  "ZORA_FACTORY": "0x...",
  "ZORA_FACTORY_IMPL": "0x...",
  "COIN_V4_IMPL": "0x...",
  "CREATOR_COIN_IMPL": "0x...",
  "ZORA_V4_COIN_HOOK": "0x...",
  "ZORA_HOOK_REGISTRY": "0x...",
  "TRUSTED_MSG_SENDER_LOOKUP": "0x...",
  "HOOK_UPGRADE_GATE": "0x...",
  "ORDER_BOOK_AUTHORITY": "0x...",
  "ZORA_LIMIT_ORDER_BOOK": "0x...",
  "ZORA_ROUTER": "0x...",
  "COIN_VERSION": "2.3.1"
}
```

### Development Chain Config

Located at `chainConfigs/8453_dev.json`:

```json
{
  "PROXY_ADMIN": "0x...",
  "UNISWAP_V4_POOL_MANAGER": "0x...",
  "UNISWAP_SWAP_ROUTER": "0x...",
  "UNISWAP_V4_POSITION_MANAGER": "0x...",
  "UNISWAP_UNIVERSAL_ROUTER": "0x...",
  "DOPPLER_AIRLOCK": "0x...",
  "ZORA_RECIPIENT": "0x...",
  "WETH": "0x..."
}
```

## Advantages of Atomic Deployment

### 1. Correct Dependency Order

The script automatically handles all dependencies:

- Factory proxy deployed first to establish address
- LOB deployed before hook (hook needs LOB address)
- Hook deployed before factory impl (impl needs hook address)

### 2. All-or-Nothing Deployment

If any step fails, the entire deployment reverts:

- No partial deployments
- No manual cleanup needed
- Easy to retry

### 3. Single Source of Truth

All deployment logic in one script:

- Easy to understand flow
- Easy to modify
- Easy to audit

### 4. Automatic State Management

Deployment addresses saved only on success:

- Prevents invalid state
- Atomic file write
- Easy rollback

## Development vs Production

| Aspect          | Development (`DEV=true`) | Production              |
| --------------- | ------------------------ | ----------------------- |
| Deployment File | `8453_dev.json`          | `8453.json`             |
| Chain Config    | `8453_dev.json`          | `8453.json`             |
| Factory Proxy   | Regular CREATE           | Regular CREATE          |
| LOB/Router      | CREATE2 (deterministic)  | CREATE2 (deterministic) |
| Hook Registry   | CREATE2 (deterministic)  | CREATE2 (deterministic) |
| Network         | Base Mainnet             | Base Mainnet            |
| Use Case        | Testing/iteration        | Production deployments  |
| PROXY_ADMIN     | Dev multisig             | Production multisig     |

## Troubleshooting

### Deployment Reverts

If deployment fails:

1. Check the error message to identify which step failed
2. Common issues:
   - Insufficient funds
   - PROXY_ADMIN not deployed
   - Chain config missing addresses
   - Network connectivity

### Address Mismatches

If addresses don't match expectations:

- Factory proxy uses CREATE (non-deterministic)
- Each deployment gets new factory address
- LOB, router, and hook registry use CREATE2 (deterministic)

### Clean Slate Deployment

To start fresh:

1. Delete or backup `addresses/8453_dev.json`
2. Run deployment script again
3. All contracts will be deployed with new addresses

## Environment Variable Details

The `DEV` environment variable is checked by:

```solidity
function isDevEnvironment() internal view returns (bool) {
  return vm.envOr("DEV", false);
}
```

This function is used by:

- `addressesFile()`: Returns `8453_dev.json` when `DEV=true`
- `chainConfigPath()`: Returns `chainConfigs/8453_dev.json` when `DEV=true`

## Best Practices

1. **Always simulate first**: Run without `--broadcast` to test
2. **Verify contracts**: Add `--verify` flag for transparency
3. **Use separate keys**: Different private keys for dev vs prod
4. **Document addresses**: Keep track of deployed contract addresses
5. **Test thoroughly**: Test on dev deployment before touching production

## Migration to Production

When ready to deploy to production:

1. Test thoroughly on dev deployment
2. Remove `DEV=true` from command
3. Use production private key
4. Run simulation first
5. Broadcast to production

```bash
# Production deployment (no DEV flag)
forge script script/DeployAllContracts.s.sol \
  --rpc-url $BASE_RPC \
  --private-key $PRODUCTION_PRIVATE_KEY \
  --broadcast \
  --verify
```

## Summary

The `DEV=true` flag enables:

- ✅ Safe testing on Base mainnet
- ✅ Separate deployment state
- ✅ Atomic deployment process
- ✅ Easy iteration and debugging
- ✅ No impact on production deployments

For questions or issues, consult the main [README.md](./README.md) or check the deployment script source code.
