# @zoralabs/incentive-contracts

## 0.2.0

### Minor Changes

- 74d12510: Add Zora incentive claim contract with KYC verification

  - New ZoraIncentiveClaim contract for token allocation claiming
  - Backend-signed KYC verification with EIP712 signatures
  - Support for multiple concurrent periods and single period claiming
  - Comprehensive access control with owner/kyc/allocation setter roles
  - Period expiry
