# Zora Sparks Contracts Deployments

Contains deployment scripts, deployed addresses and versions for the Zora Sparks Contracts.

## Package contents

- [Deployment scripts](./script/) for deployment Zora Sparks Contracts
- [Deployed addresses](./addresses/) containing deployed addresses and contract versions by chain.
- [Published npm package](https://www.npmjs.com/package/@zoralabs/mints-deployments) containing [wagmi cli](https://wagmi.sh/cli/getting-started) generated typescript bundle of deployed contract abis and addresses.

## Deploying to a new chain

Deploy the [ProxyDeployer](src/DeterministicUUPSProxyDeployer.sol):

```sh
forge script script/DeployProxyDeployer.s.sol {rest of deployment config}
```

Add an empty address.json in `addresses/${chainId}.json`

Deploy the mints manager implementation, which will update the above created addresses.json with the new implementation address and version:

```sh
forge script script/DeploySparksManagerImpl.s.sol {rest of deployment config}
```

Deploy the `ZoraSparksManager`, which when initialized will deploy the `ZoraSparks1155` contract:

```sh
yarn tsx scripts/deploySparksDeterminisitic.ts {chain-name}
```

To verify that deployed proxy contract, run the printed out verification command from the above step.
