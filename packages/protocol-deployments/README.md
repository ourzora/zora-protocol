# Zora Protocol Deployments

Contains deployment scripts, deployed addresses and versions for the Zora Protocol.

## Package contents

* [Deployment scripts](./scripts/) for deployment Zora Protocol Contracts
* [Deployed addresses](./addresses/) containing deployed addresses and contract versions by chain.
* [Published npm package](https://www.npmjs.com/package/@zoralabs/protocol-deployments) containing [wagmi cli](https://wagmi.sh/cli/getting-started) generated typescript bundle of deployed contract abis and addresses.

## Npm package usage 

Import abis and addresses for a contract from the package:

```typescript
import { zoraCreator1155FactoryImplConfig } from "@zoralabs/protocol-deployments";

// get addresses and abi for zora creator 1155 factory:
const { addresses, abi } = zoraCreator1155FactoryImplConfig;
```
