# Zora MINTS

A new mechanism for minting on Zora.

### Background

Previously, collectors pass send a fixed value of ETH to mint on a creator's contract.

MINTs are a new form factor of this value, represented as an 1155 token, enabling:

- collectors to purchase the value of their MINTs in advance, based on the current price of the MINTs
- collectors to use these MINTs at a future time to mint a Zora Creator ERC-1155 NFT, regardless of if the price to purchase a new MINT changes.

1 MINT = 1 Mint

### Design

The Zora MINTs 1155 contract is an immutable ERC-1155 contract that allows for the minting and
collecting of Zora Creator ERC-1155 NFTs using MINTs.

MINTs are ERC-1155s, with each token ID having a fixed value in ETH or ERC20 that can be
minted at that ETH or ERC20 value. The owner of a MINT can either redeem it or use it to
collect a Zora Creator ERC-1155 NFT. When it is used to collect a Zora Creator
ERC-1155 NFT, the MINT is burned and the underlying value is distributed to a
set of recipients in the form of fees and rewards, with the percentage split
configured in the creator contract. When a MINT is redeemed, the underlying
value is distributed to a desired recipient, and the MINT is burned.

The `ZoraMintsManager` is an administrated and upgradeble that contract controls which MINT token id can be minted for each currency type,
thus defining the current price for collecting a MINT in that currency type.  
While it controls the logic around which MINTs can be minted, once a MINT is minted, the corresponding value is deposited into the
immutable `ZoraMints1155` contract; only the owner of the MINTs can access the underlying deposited funds by redeming the MINTs or choose to do with their MINTs, and since that contract is immutable these rules could never change.

The `ZoraMints1155` and `ZoraMintsManager` contracts are deployed deterministically to the same address on all chains:

- `ZoraMints1155`: [0x7777777d57c1C6e472fa379b7b3B6c6ba3835073](https://explorer.zora.energy/address/0x7777777d57c1C6e472fa379b7b3B6c6ba3835073)
- `ZoraMintsManager`: [0x77777770cA269366c7208aFcF36FE2C6F7f7608B](https://explorer.zora.energy/address/0x77777770cA269366c7208aFcF36FE2C6F7f7608B)
