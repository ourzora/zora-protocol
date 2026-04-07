# @zoralabs/incentive-contracts

## 0.2.1

### Patch Changes

- cf72490f: Remove indexed label from AllocationsSet event to prevent indexer parsing error

  - Remove `indexed` keyword from `label` parameter in `AllocationsSet` event
  - This prevents potential issues with event indexing and parsing

- 9c7a8600: Add Base chain contract address

  - Add addresses/8453.json with ZORA_INCENTIVE_CLAIM contract address for Base chain deployment

## 0.2.0

### Minor Changes

- 74d12510: Add Zora incentive claim contract with KYC verification

  - New ZoraIncentiveClaim contract for token allocation claiming
  - Backend-signed KYC verification with EIP712 signatures
  - Support for multiple concurrent periods and single period claiming
  - Comprehensive access control with owner/kyc/allocation setter roles
  - Period expiry
