# Limit Order Deployment Guide

This guide covers deploying ZoraLimitOrderBook and SwapWithLimitOrders contracts using ImmutableCreate2Factory with Turnkey for secure transaction signing.

## Overview

The deployment process has two steps:

1. **Generate deterministic parameters** - Mine salts to create "7777777" vanity addresses
2. **Deploy with Turnkey** - Execute sequential deployment with validation

## Prerequisites

### 1. Turnkey Setup

Configure Turnkey environment variables in `.env`:

```bash
TURNKEY_API_PUBLIC_KEY=your_turnkey_api_public_key
TURNKEY_API_PRIVATE_KEY=your_turnkey_api_private_key
TURNKEY_ORGANIZATION_ID=your_turnkey_organization_id
TURNKEY_PRIVATE_KEY_ID=your_turnkey_private_key_id
TURNKEY_TARGET_ADDRESS=your_turnkey_target_address

# DEPLOYER must match TURNKEY_TARGET_ADDRESS
DEPLOYER=your_turnkey_target_address
```

**CRITICAL:** `DEPLOYER` must equal `TURNKEY_TARGET_ADDRESS`. The mined salts encode the deployer address, so only that address can deploy the contracts.

### 2. Check for Outstanding Changesets

**Before deploying**, verify there are no outstanding changesets for contract packages:

```bash
cd ../.. # Navigate to monorepo root
pnpm changeset status
```

If there are outstanding changesets for `@zoralabs/limit-orders` or `@zoralabs/coins`:

```bash
pnpm update-version  # Apply changesets to update versions
pnpm build          # Build with updated versions
```

**Why this is critical**: Changesets update contract version numbers. We must deploy contracts with their correct version so the addresses in `@zoralabs/protocol-deployments` match the published contract versions.

### 3. Install Dependencies

```bash
pnpm install
```

## Deployment Steps

### Step 1: Generate Deterministic Parameters

Generate salts and expected addresses for both contracts:

```bash
./scripts/run-forge-script.sh GenerateLimitOrderParams.s.sol base --ffi
```

**What it does:**

- Mines salts where first 20 bytes encode the deployer address (Turnkey address)
- Generates "7777777" vanity addresses using ImmutableCreate2Factory
- Saves configurations to `deterministicConfig/zoraLimitOrderBook.json` and `deterministicConfig/zoraRouter.json`
- Updates deployment file at `addresses/8453.json`

**Output:**

```
Deployer (caller): 0x680E26B472d8cae8148ee21FCAd6A69D73766436
ZORA_LIMIT_ORDER_BOOK: 0x77777774d70B1E9D6f705f99dA7c02e4E768dF09
ZORA_ROUTER: 0x7777777A1F22faaB216f502B5D0BAAdE8c734F30
```

### Step 2: Deploy with Turnkey

#### Dry Run (Simulation Only)

First, test the deployment with a dry run:

```bash
pnpm deploy-limit-orders 8453 --dry-run
```

**What it does:**

- Creates Turnkey account connection
- Simulates both contract deployments using `simulateContract`
- Verifies expected addresses match simulation results
- **Does NOT send any transactions**

**Output:**

```
=== Simulating ZoraLimitOrderBook Deployment ===
✅ Simulation successful
   Result: 0x77777774d70B1E9D6f705f99dA7c02e4E768dF09
   Expected: 0x77777774d70B1E9D6f705f99dA7c02e4E768dF09

=== Simulating SwapWithLimitOrders Deployment ===
✅ Simulation successful
   Result: 0x7777777A1F22faaB216f502B5D0BAAdE8c734F30
   Expected: 0x7777777A1F22faaB216f502B5D0BAAdE8c734F30

✅ All simulations passed!

=== Dry Run Complete ===
No transactions were sent.
```

#### Live Deployment

Once dry run succeeds, deploy for real:

```bash
pnpm deploy-limit-orders 8453
```

**What it does:**

- Simulates both deployments (same as dry run)
- Deploys ZoraLimitOrderBook first, waits for confirmation
- Verifies first deployment succeeded before continuing
- Deploys SwapWithLimitOrders second, waits for confirmation
- **Automatically verifies contracts** on the block explorer using `forge verify-contract`

**Output:**

```
=== Deploying ZoraLimitOrderBook ===
Transaction hash: 0x...
Waiting for confirmation...
✅ Deployed at block 12345678, Gas used: 3500000

=== Deploying SwapWithLimitOrders ===
Transaction hash: 0x...
Waiting for confirmation...
✅ Deployed at block 12345679, Gas used: 2800000

=== Deployment Complete ===
✅ Both contracts deployed successfully
ZORA_LIMIT_ORDER_BOOK: 0x77777774d70B1E9D6f705f99dA7c02e4E768dF09
ZORA_ROUTER: 0x7777777A1F22faaB216f502B5D0BAAdE8c734F30
```

## Technical Details

### Salt Encoding

The salt's first 20 bytes encode the deployer address, ensuring only the Turnkey address can deploy:

```
Salt: 0x680e26b472d8cae8148ee21fcad6a69d73766436fae357a4904c69284ef8b586
      └─────────────────────────────────┘
         First 20 bytes = deployer address
```

### ImmutableCreate2Factory

Uses the standard ImmutableCreate2Factory at `0x0000000000FFe8B47B3e2130213B802212439497`:

- `safeCreate2(bytes32 salt, bytes initializationCode) returns (address)`
- Reverts if contract already exists at computed address
- Ensures deterministic deployment across chains

### Sequential Deployment with Validation

Deploys contracts sequentially with validation between steps:

- Deploys ZoraLimitOrderBook first
- Validates first deployment succeeded before continuing
- Deploys SwapWithLimitOrders second
- If the second deployment fails, the first contract remains deployed

## Configuration Files

### Deterministic Config Structure

`deterministicConfig/zoraLimitOrderBook.json`:

```json
{
  "salt": "0x680e26b472d8cae8148ee21fcad6a69d73766436fae357a4904c69284ef8b586",
  "deployedAddress": "0x77777774d70B1E9D6f705f99dA7c02e4E768dF09",
  "creationCode": "0x...",
  "constructorArgs": "0x...",
  "contractName": "ZoraLimitOrderBook"
}
```

### Deployment Address Structure

`addresses/8453.json`:

```json
{
  "ZORA_FACTORY": "0x777777751622c0d3258f214F9DF38E35BF45baF3",
  "ZORA_HOOK_REGISTRY": "0x777777C4c14b133858c3982D41Dbf02509fc18d7",
  "ZORA_LIMIT_ORDER_BOOK": "0x77777774d70B1E9D6f705f99dA7c02e4E768dF09",
  "ZORA_ROUTER": "0x7777777A1F22faaB216f502B5D0BAAdE8c734F30"
}
```

## Troubleshooting

### "Address mismatch" during simulation

The simulated address doesn't match the expected address. This usually means:

- Constructor arguments changed since parameters were generated
- Wrong deployer address in `.env`
- **Solution**: Regenerate parameters with Step 1

### "Salt not found in result"

The salt mining failed. This can happen if:

- `cast` command not available
- FFI not enabled
- **Solution**: Ensure Foundry is installed and `--ffi` flag is used

### "Turnkey permission denied"

Turnkey policy doesn't allow the user to sign transactions:

- **Solution**: Update Turnkey policy to grant signing permissions to your user ID

### "Contract already deployed"

The contract already exists at the target address:

- **Solution**: Either use existing deployment or change salt (requires new vanity address)

### DEPLOYER Address Mismatch

**Critical:** The `DEPLOYER` address must match your `TURNKEY_TARGET_ADDRESS`.

**Why this matters:**

- When mining salts, the `--caller` flag is set to the `DEPLOYER` address
- The mined salt encodes the deployer address in the first 20 bytes
- Only the specified deployer can use that salt to deploy the contract
- If addresses don't match, deployment will fail or produce wrong addresses

**Solution:**

```bash
# In .env, ensure these match:
TURNKEY_TARGET_ADDRESS=0xYourTurnkeyAddress
DEPLOYER=0xYourTurnkeyAddress  # Must be the same!
```

After updating, regenerate parameters:

```bash
./scripts/run-forge-script.sh GenerateLimitOrderParams.s.sol base --ffi
```

## Security Notes

- **Private Keys**: Turnkey manages private keys securely; they never leave Turnkey's infrastructure
- **Salt Protection**: First 20 bytes of salt must match caller, preventing front-running
- **Sequential Deployment**: Contracts deploy sequentially with validation between steps
- **Simulation First**: Always run dry-run before live deployment
- **Private keys never exposed**: The `.env` file is never read by Claude Code

## Next Steps After Deployment

### 1. Verify Contracts

Verification happens automatically. If it fails due to rate limiting or network issues, you can reverify manually (see Manual Reverification below).

### 2. Create Changeset for Protocol Deployments

**IMPORTANT**: After any deployment (dev or production), create a changeset for `@zoralabs/protocol-deployments`.

See [CLAUDE.md - Protocol-Deployments Changesets](../../CLAUDE.md#protocol-deployments-changesets-for-contract-deployments) for detailed instructions on the proper format and requirements.

**Pre-Deployment Changeset Check:**

Before deploying, ensure there are **no outstanding changesets** for `@zoralabs/limit-orders` or `@zoralabs/coins`:

```bash
pnpm changeset status
```

If there are outstanding changesets for these packages:

1. Run `pnpm update-version` to apply them
2. This ensures contract versions are updated before deployment
3. Then deploy with the correct versioned contracts

**Why this matters**: Changesets for contract packages update the version numbers. We must deploy contracts with their correct version so the addresses in `@zoralabs/protocol-deployments` match the published contract versions.

### 3. Update Documentation and Test Integration

- Add deployed addresses to relevant docs
- Verify contracts work with existing system

### Manual Reverification

If automatic verification fails, you can reverify the contracts manually using the contract addresses:

```bash
# Verify ZoraLimitOrderBook
forge verify-contract 0x77777774d70B1E9D6f705f99dA7c02e4E768dF09 ZoraLimitOrderBook --guess-constructor-args $(chains base --deploy)

# Verify SwapWithLimitOrders
forge verify-contract 0x7777777A1F22faaB216f502B5D0BAAdE8c734F30 SwapWithLimitOrders --guess-constructor-args $(chains base --deploy)
```

Replace the addresses with your deployed contract addresses.

## Commands Quick Reference

```bash
# Generate deterministic parameters
./scripts/run-forge-script.sh GenerateLimitOrderParams.s.sol base --ffi

# Dry run (simulation only)
pnpm deploy-limit-orders 8453 --dry-run

# Live deployment (includes automatic verification)
pnpm deploy-limit-orders 8453
```

## Script Reference

### `run-forge-script.sh`

Secure wrapper for running Forge scripts with private key from `.env`.

**Flags:**

- `--deploy`: Broadcast and verify the deployment
- `--resume`: Resume and reverify a previous deployment
- `--dev`: Use development mode (DEV=true)
- `--ffi`: Enable FFI for external commands

### `GenerateLimitOrderParams.s.sol`

Mines deterministic salts for "7777777" addresses.

**Requirements:**

- `DEPLOYER` address in `.env`
- ZoraFactory and ZoraHookRegistry must be deployed
- Must run with `--ffi` flag

### `deployLimitOrdersWithTurnkey.ts`

Deploys limit order contracts using Turnkey.

**Usage:**

```bash
pnpm deploy-limit-orders <chain_id> [--dry-run]
```

**Flags:**

- `--dry-run`: Run simulation only, don't send transactions

**What it does:**

1. Connects to Turnkey
2. Simulates both deployments
3. (If not dry-run) Deploys ZoraLimitOrderBook and waits for confirmation
4. Verifies first deployment succeeded
5. Deploys SwapWithLimitOrders and waits for confirmation
6. Displays results
7. Automatically verifies contracts on block explorer

**Requirements:**

- Turnkey environment variables configured
- Deterministic configs generated
- viem 2.45.0+ for improved compatibility
- Foundry installed (for automatic verification)
