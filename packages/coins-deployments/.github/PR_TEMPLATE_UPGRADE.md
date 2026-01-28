# Deploy Coin Hooks v[COIN_VERSION] for [NETWORK_NAME]

## Summary

[BRIEF_SUMMARY_OF_CHANGES]

## Changes

### Core Changes
- [CHANGE_1]
- [CHANGE_2]
- [CHANGE_N]

### Deployments
- Deployed [CONTRACT_NAMES] to [NETWORK_NAME]

## Deployed Contracts

### [NETWORK_NAME] Dev

[DEPLOYED_CONTRACTS_LIST_DEV]

### [NETWORK_NAME] Main (Production)

[DEPLOYED_CONTRACTS_LIST_MAIN]

## Multisig Upgrade Instructions

### [NETWORK_NAME] Dev

Execute the following transaction in the [NETWORK_NAME] dev multisig:

- **Multisig**: `[MULTISIG_ADDRESS_DEV]` ([safe](https://app.safe.global/home?safe=base:[MULTISIG_ADDRESS_DEV]))
- **Target**: `[FACTORY_PROXY_ADDRESS_DEV]` ([explorer](https://basescan.org/address/[FACTORY_PROXY_ADDRESS_DEV]))
- **Function**: `upgradeToAndCall(address,bytes)`
- **Call Data**:
  ```
  [UPGRADE_CALL_DATA_DEV]
  ```
- **New Implementation**: `[FACTORY_IMPL_ADDRESS_DEV]` ([explorer](https://basescan.org/address/[FACTORY_IMPL_ADDRESS_DEV]))

### [NETWORK_NAME] Main (Production)

Execute the following transaction in the [NETWORK_NAME] main multisig:

- **Multisig**: `[MULTISIG_ADDRESS_MAIN]` ([safe](https://app.safe.global/home?safe=base:[MULTISIG_ADDRESS_MAIN]))
- **Target**: `[FACTORY_PROXY_ADDRESS_MAIN]` ([explorer](https://basescan.org/address/[FACTORY_PROXY_ADDRESS_MAIN]))
- **Function**: `upgradeToAndCall(address,bytes)`
- **Call Data**:
  ```
  [UPGRADE_CALL_DATA_MAIN]
  ```
- **New Implementation**: `[FACTORY_IMPL_ADDRESS_MAIN]` ([explorer](https://basescan.org/address/[FACTORY_IMPL_ADDRESS_MAIN]))
