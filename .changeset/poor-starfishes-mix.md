---
"@zoralabs/coins-deployments": patch
---

Fix deployment architecture to prevent TrustedMsgSenderProviderLookup redeployment

- Remove TrustedMsgSenderProviderLookup deployment from deployImpls() function
- Add validateExternalDependencies() function to validate all external dependencies before deployment
- Ensure lookup contract is only deployed once using DeployTrustedMsgSenderLookup.s.sol script
