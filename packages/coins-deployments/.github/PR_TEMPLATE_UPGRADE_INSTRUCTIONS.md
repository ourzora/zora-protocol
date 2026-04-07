# Agent Instructions: Populating Upgrade PR Template

When creating a PR for contract upgrades, use the template at `.github/PR_TEMPLATE_UPGRADE.md` and populate it as follows:

## Step 1: Read Deployment Data

1. **Read address files** for the deployed contracts:
   - Dev: `addresses/[CHAIN_ID]_dev.json`
   - Main: `addresses/[CHAIN_ID].json`

2. **Run PrintUpgradeCommand.s.sol** to get multisig upgrade instructions:
   ```bash
   # For dev
   ./scripts/run-forge-script.sh PrintUpgradeCommand.s.sol [chain] --dev

   # For main/production
   ./scripts/run-forge-script.sh PrintUpgradeCommand.s.sol [chain]
   ```

3. **Extract from the output**:
   - Multisig address
   - Target (factory proxy) address
   - Upgrade call data
   - New implementation address

## Step 2: Populate Template Variables

Replace all `[PLACEHOLDER]` values in the template:

### Network Information
- `[NETWORK_NAME]`: Network name (e.g., "Base", "Zora", "Ethereum")
- `[CHAIN_ID]`: Chain ID for the network (e.g., 8453 for Base)
- `[COIN_VERSION]`: Value of `COIN_VERSION` from the main (production) address file

### Summary Section
- `[BRIEF_SUMMARY_OF_CHANGES]`: 1-2 sentence summary of what changed
- `[CHANGE_1]`, `[CHANGE_2]`, etc.: Bullet points of specific changes
- `[CONTRACT_NAMES]`: Names of contracts deployed (e.g., "TrustedMsgSenderProviderLookup, ContentCoin, CreatorCoin")

### Deployed Contracts Lists

**Important**: Only include contracts that were actually deployed in this PR. Check the broadcast file to see which contracts have CREATE or CREATE2 transactions.

#### For Dev Environment (`[DEPLOYED_CONTRACTS_LIST_DEV]`):

1. Read the broadcast file: `broadcast/[SCRIPT_NAME]/[CHAIN_ID]/run-latest.json`
2. Find all transactions with `transactionType` of "CREATE" or "CREATE2"
3. For each deployed contract, create a line in this format:
   ```
   - **[ContractName]**: `[address]` ([verified](https://basescan.org/address/[address]))
   ```

**Contract Name Mapping** (use contractName from broadcast):
- `ContentCoin` → "ContentCoin"
- `CreatorCoin` → "CreatorCoin"
- `ZoraV4CoinHook` → "ZoraV4CoinHook"
- `ZoraFactoryImpl` → "ZoraFactoryImpl"
- `TrustedMsgSenderProviderLookup` → "TrustedMsgSenderProviderLookup"

Example:
```
- **ContentCoin**: `0x78fD96b3acd95C4a4C6F6cd1Ca64F9390C593569` ([verified](https://basescan.org/address/0x78fD96b3acd95C4a4C6F6cd1Ca64F9390C593569))
- **CreatorCoin**: `0x75Ace0140C2A16a523747C056574375721E38e49` ([verified](https://basescan.org/address/0x75Ace0140C2A16a523747C056574375721E38e49))
- **ZoraV4CoinHook**: `0x3E7A8bf2134EC7695aF6F89328132b15e53A10C0` ([verified](https://basescan.org/address/0x3E7A8bf2134EC7695aF6F89328132b15e53A10C0))
- **ZoraFactoryImpl**: `0x05a068EF1d7A03896cB2A531b3e82F418faA0653` ([verified](https://basescan.org/address/0x05a068EF1d7A03896cB2A531b3e82F418faA0653))
```

#### For Main Environment (`[DEPLOYED_CONTRACTS_LIST_MAIN]`):

Same process as dev, but use the production broadcast file (without `_dev` in addresses)

### Multisig Upgrade Instructions - Dev
From `PrintUpgradeCommand.s.sol` output with `--dev`:
- `[MULTISIG_ADDRESS_DEV]`: "Multisig:" value from output
- `[FACTORY_PROXY_ADDRESS_DEV]`: "Target (the factory proxy):" value from output
- `[UPGRADE_CALL_DATA_DEV]`: "Upgrade call:" value from output (the hex string)
- `[FACTORY_IMPL_ADDRESS_DEV]`: Extract from "Args:" (first address after "Args:")

### Multisig Upgrade Instructions - Main
From `PrintUpgradeCommand.s.sol` output without `--dev`:
- `[MULTISIG_ADDRESS_MAIN]`: "Multisig:" value from output
- `[FACTORY_PROXY_ADDRESS_MAIN]`: "Target (the factory proxy):" value from output
- `[UPGRADE_CALL_DATA_MAIN]`: "Upgrade call:" value from output (the hex string)
- `[FACTORY_IMPL_ADDRESS_MAIN]`: Extract from "Args:" (first address after "Args:")

## Step 3: Update Links

**Note**: Template assumes Base mainnet. Links use:
- Block Explorer: `basescan.org`
- Safe Network Prefix: `base` (format: `https://app.safe.global/home?safe=base:[ADDRESS]`)

## Step 4: Validate All Links

Before submitting the PR, verify that:
1. All contract addresses are checksummed (proper case)
2. All block explorer links work
3. All contracts show as verified on the block explorer
4. Multisig addresses match the expected addresses for the network
5. Factory proxy addresses match the known proxy addresses

## Example: Base Network

For Base (chain ID 8453):

**Dev address file**: `addresses/8453_dev.json`
```json
{
  "COIN_VERSION": "2.4.2",
  "TRUSTED_MSG_SENDER_LOOKUP": "0xA6952EdFe158F383Cc2587184eca92a1c0d87273",
  "COIN_V4_IMPL": "0x78fD96b3acd95C4a4C6F6cd1Ca64F9390C593569",
  "CREATOR_COIN_IMPL": "0x75Ace0140C2A16a523747C056574375721E38e49",
  "ZORA_V4_COIN_HOOK": "0x3E7A8bf2134EC7695aF6F89328132b15e53A10C0",
  "ZORA_FACTORY_IMPL": "0x05a068EF1d7A03896cB2A531b3e82F418faA0653"
}
```

**PrintUpgradeCommand output (dev)**:
```
Multisig: 0xEAB37fbA9E4F99602815E173A7FeAee0f4eF980B
Target (the factory proxy): 0xfAf4978830e099F0952eBabC89fEb0B18Ba771D8
Upgrade call:
0x4f1ef28600000000000000000000000005a068ef1d7a03896cb2a531b3e82f418faa065300000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000000
Function to call: upgradeToAndCall
Args:  0x05a068EF1d7A03896cB2A531b3e82F418faA0653,"
```

Results in:
- `[MULTISIG_ADDRESS_DEV]` = `0xEAB37fbA9E4F99602815E173A7FeAee0f4eF980B`
- `[FACTORY_PROXY_ADDRESS_DEV]` = `0xfAf4978830e099F0952eBabC89fEb0B18Ba771D8`
- `[UPGRADE_CALL_DATA_DEV]` = `0x4f1ef28600000000000000000000000005a068ef1d7a03896cb2a531b3e82f418faa065300000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000000`
- `[FACTORY_IMPL_ADDRESS_DEV]` = `0x05a068EF1d7A03896cB2A531b3e82F418faA0653`

## Base Network Details

### Base (8453)
- Block Explorer: `basescan.org`
- Safe Network Prefix: `base`
- Dev Multisig: `0xEAB37fbA9E4F99602815E173A7FeAee0f4eF980B`
- Main Multisig: `0x004d6611884B4A661749B64b2ADc78505c3e1AB3`
- Main Factory Proxy: `0x777777751622c0d3258f214F9DF38E35BF45baF3`
