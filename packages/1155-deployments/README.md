# Zora Protocol 1155 Contract Deployments

Contains deployment scripts, deployed addresses and versions for the Zora 1155 Contracts.

## Package contents

- [Deployment scripts](./script/) for deployment Zora Protocol Contracts
- [Deployed addresses](./addresses/) containing deployed addresses and contract versions by chain.
- [Published npm package](https://www.npmjs.com/package/@zoralabs/1155-deployments) containing [wagmi cli](https://wagmi.sh/cli/getting-started) generated typescript bundle of deployed contract abis and addresses.

## Npm package usage

Import abis and addresses for a contract from the package:

```typescript
import { zoraCreator1155FactoryImplConfig } from "@zoralabs/1155-deployments";

// get addresses and abi for the zora creator 1155 factory:
const { addresses, abi } = zoraCreator1155FactoryImplConfig;
```
