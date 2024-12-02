# Zora Protocol Rewards

Zora is about bringing creativity onchain. Protocol Rewards is our latest offering for creators and developers to earn from their contributions to our growing ecosystem. 

This repository features:
- The `ERC721Rewards` and `ERC1155Rewards` abstract smart contracts which handle reward computation and routing for Zora [ERC-721](https://github.com/ourzora/zora-drops-contracts) and [ERC-1155](https://github.com/ourzora/zora-1155-contracts) NFT mints
- The `ProtocolRewards` singleton smart contract used to deposit and withdraw rewards

Documentation is available at [docs.zora.co](https://docs.zora.co).

## Implementation Caveats

The `ProtocolRewards` contract has an implementation caveat. If you send any value to a zero (`address(0)`) address in `depositRewards`, that value is implicitly burned by being locked in the contract at the zero address. The function will not revert or redirect those funds as currently designed. We may re-visit this design in the future but for the release of  v1.1 this is the current and expected behavior.

## Deployed Addresses

`ProtocolRewards` v1.1 is deterministically deployed at 0x7777777F279eba3d3Ad8F4E708545291A6fDBA8B.

Current Supported Chains:
- Zora Mainnet
- Zora Goerli
- Ethereum Mainnet
- Ethereum Goerli
- OP Mainnet
- OP Goerli
- Base Mainnet
- Base Goerli

## Install

To interact with the `ProtocolRewards` contract:
```sh
pnpm add @zoralabs/protocol-rewards
```
