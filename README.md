# Zora Protocol

This repository is a monorepo for the Zora Protocol

In it you will find:

- [Zora 1155 Contracts](./packages/1155-contracts)
- [Protocol Rewards](./packages/protocol-rewards)
- [Protocol Deployments](./packages/protocol-deployments)

## Official docs

[View the official docs](https://docs.zora.co/docs/smart-contracts/creator-tools/intro)

## Setup

Install prerequisites:

- [Node.js and yarn](https://classic.yarnpkg.com/lang/en/docs/install/#mac-stable)
- [Foundry](https://book.getfoundry.sh/getting-started/installation)

Install dependencies:

    yarn

Build contracts:

    yarn build

Run tests:

    yarn test

Run in development mode (watch tests):

    yarn dev

## Bug Bounty

5 ETH for any critical bugs that could result in loss of funds. Rewards will be given for smaller bugs or ideas.

## Development workflow

See [DEVELOPMENT.md](./DEVELOPMENT.md)

## Installing contracts with Forge

Our contracts import dependencies via npm/node_modules, so if using `forge install`, additional steps are required to install contract dependencies using [yarn](https://classic.yarnpkg.com/lang/en/docs/install/) and setup their mappings:

1. Make sure to have yarn installed [yarn](https://classic.yarnpkg.com/lang/en/docs/install/)
2. Install contracts with forge:

    forge install ourzora/zora-protocol@main

3. Install npm dependencies for zora protocol contracts:

    cd lib/zora-protocol && yarn

4. Add the following remappings to your project:

```txt
ourzora/1155-contracts/src/=lib/zora-protocol/packages/1155-contracts/src/
_imagine=lib/zora-protocol/packages/1155-contracts/_imagine/

ds-test/=lib/zora-protocol/node_modules/ds-test/src/
forge-std/=lib/zora-protocol/node_modules/forge-std/src/
@zoralabs/openzeppelin-contracts-upgradeable/=lib/zora-protocol/node_modules/@zoralabs/openzeppelin-contracts-upgradeable/
@zoralabs/protocol-rewards/src/=lib/zora-protocol/node_modules/@zoralabs/protocol-rewards/src/
@openzeppelin/contracts/=lib/zora-protocol/node_modules/@openzeppelin/contracts/
solemate/=lib/zora-protocol/node_modules/solemate/src/
solady/=lib/zora-protocol/node_modules/solady/src/
```

Now in your solidity code, you should be able to import contracts like so:

```
import { ZoraCreator1155Impl } from "ourzora/1155-contracts/src/nft/ZoraCreator1155Impl.sol";
```

