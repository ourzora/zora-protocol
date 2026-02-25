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
NETWORK=zora pnpm run build:subgraph

```

NETWORK needs to be a name of a valid network configuration file in `config/`.

**Note:** This package has been moved to legacy and uses `build:subgraph` instead of `build` to avoid conflicts with the root build system. Use `build:subgraph` for subgraph-specific builds.

After building, you can use the graph cli to deploy the built subgraph for the network specified above.

# ABIs

ABIs are automatically copied to the `abis` folder from the node packages on build.

ABIs that are not included in the node modules are found in the `graph-api`.
