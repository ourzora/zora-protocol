# Zora Creator Subgraph

This subgraph indexes all Zora creator contracts (both 721 and 1155) along with creator rewards.

Main entities can be found in `schema.graphql`.

To add new chains, new configuration files can be added to the `config/` folder. The config chain name needs to match the network name in the graph indexer instance used.

This subgraph uses metadata IPFS indexing and subgraph optional features.

## Installation

The graph docs: https://thegraph.academy/developers/subgraph-development-guide/

After `git clone` run `yarn` to install dependencies.


Steps to build:

```sh
NETWORK=zora pnpm run build

```

NETWORK needs to be a name of a valid network configuration file in `config/`.


After building, you can use the graph cli or goldsky cli to deploy the built subgraph for the network specified above.


## Deployment shortcuts

Only supports goldsky deploys for now:

Grafts subgraph from FROM_VERSION:

./scripts/multideploy.sh NEW_VERSION NETWORKS FROM_VERSION

./scripts/multideploy.sh 1.10.0 zora-testnet,optimism-goerli,base-goerli 1.8.0

Deploys without grafting:

./scripts/multideploy.sh NEW_VERSION NETWORKS

./scripts/multideploy.sh 1.10.0 zora-testnet,optimism-goerli,base-goerli

Deploys a new version for _all_ networks without grafting: (not typical, indexing takes a long time in many cases.)

./scripts/multideploy.sh NEW_VERSION

# ABIs

ABIs are automatically copied to the `abis` folder from the node packages on build.

ABIs that are not included in the node modules are found in the `graph-api`.