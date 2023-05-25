# ZORA 1155 Contracts

The Zora Creator 1155 Contracts are the 1155 compliment to the Zora 721 Drops Contracts. While the 721 Drops Contracts enable creators to mint unique, non-fungible tokens (NFTs), the 1155 Contracts allow creators to mint semi-fungible tokens with a set of flexible properties.

The main implementation of the Zora Creator 1155 Contracts includes the following modules:

- Metadata Control
- Royalties Control
- Minting Control
- Permissions Control
- Royalties Controls

Most controls exist on a per-contract and per-token level. Per contract level is defined as any configuration existing in the pre-reserved 0 token space.

## Official docs

[View the official docs](https://docs.zora.co/docs/smart-contracts/creator-tools/Deploy1155Contract)

## Bug Bounty

5 ETH for any critical bugs that could result in loss of funds. Rewards will be given for smaller bugs or ideas.

## Publishing a new version to npm

Generate a new changeset in your branch with:

    npx changeset

When the branch is merged to main, the versions will be automatically updated in the corresponding packages.

To publish the updated version:

    yarn publish-packages
