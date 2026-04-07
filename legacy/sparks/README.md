# Zora SPARKS

A new mechanism for minting on Zora.

### Background

Previously, collectors pass send a fixed value of ETH to mint on a creator's contract.

SPARKs are a new form factor of this value, represented as an 1155 token, enabling:

- collectors to purchase the value of their SPARKs in advance, based on the current price of the SPARKs
- collectors to use these SPARKs at a future time to mint a Zora Creator ERC-1155 NFT, regardless of if the price to purchase a new SPARK changes.

1 SPARK = 1 Mint

### Design

The Zora SPARKs 1155 contract is an immutable ERC-1155 contract that allows for the minting and
collecting of Zora Creator ERC-1155 NFTs using SPARKs.

SPARKs are ERC-1155s, with each token ID having a fixed value in ETH or ERC20 that can be
minted at that ETH or ERC20 value. The owner of a SPARK can either redeem it or use it to
collect a Zora Creator ERC-1155 NFT. When it is used to collect a Zora Creator
ERC-1155 NFT, the SPARK is burned and the underlying value is distributed to a
set of recipients in the form of fees and rewards, with the percentage split
configured in the creator contract. When a SPARK is redeemed, the underlying
value is distributed to a desired recipient, and the SPARK is burned.

The `ZoraSparksManager` is an administrated and upgradeable that contract controls which SPARK token id can be minted for each currency type,
thus defining the current price for collecting a SPARK in that currency type.  
While it controls the logic around which SPARKs can be minted, once a SPARK is minted, the corresponding value is deposited into the
immutable `ZoraSparks1155` contract; only the owner of the SPARKs can access the underlying deposited funds by redeming the SPARKs or choose to do with their SPARKs, and since that contract is immutable these rules could never change.

The `ZoraSparks1155` and `ZoraSparksManager` contracts are deployed deterministically to the same address on all chains:

- `ZoraSparks1155`: [0x7777777d57c1C6e472fa379b7b3B6c6ba3835073](https://explorer.zora.energy/address/0x7777777d57c1C6e472fa379b7b3B6c6ba3835073)
- `ZoraSparksManager`: [0x77777770cA269366c7208aFcF36FE2C6F7f7608B](https://explorer.zora.energy/address/0x77777770cA269366c7208aFcF36FE2C6F7f7608B)

## Deploying to a new chain

Deploy the [ProxyDeployer](src/DeterministicUUPSProxyDeployer.sol):

```sh
forge script script/DeployProxyDeployer.s.sol:DeployProxyDeployer {rest of deployment config}
```

Add an empty address.json in `addresses/${chainId}.json`

Deploy the mints manager implementation, which will update the above created addresses.json with the new implementation address and version:

```sh
forge script script/DeploySparksManagerImpl.s.sol:DeploySparksManagerImpl {rest of deployment config}
```

Deploy the `ZoraSparksManager`, which when initialized will deploy the `ZoraSparks1155` contract:

```sh
yarn tsx scripts/deploySparksDeterministic.ts {chain-name}
```

To verify that deployed proxy contract, run the printed out verification command from the above step.

To ensure verification completes, foundry may need to be downgraded to `nightly-c4a31a624874ab36284fca4e48d2197e43a62fbe` (using `foundryup --version nightly-c4a31a624874ab36284fca4e48d2197e43a62fbe`) to make sure the verification files match.

After deploying, update the `addresses/CHAINID.json` files with the newly deployed proxy addresses manually from zero addresses.