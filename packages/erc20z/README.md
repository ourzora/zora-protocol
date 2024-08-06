## Zora Timed Sale Strategy
The Zora Sale Timed Sale Strategy introduces a new fixed price and unlocks secondary sales on Uniswap V3. New tokens minted will have a fixed price of 0.000111 ETH (111 sparks).

Upon calling setSale() a sale will be created for the 1155 NFT provided. In this function, it will also create an ERC20z token and a Uniswap V3 Pool. The ERC20z token will be used as a pool pair (WETH / ERC20z) as well as enable wrapping and unwrapping tokens from 1155 to ERC20z and vice versa.

After the sale has ended launchMarket() will be called to launch the secondary market. This will deploy liquidity into the Uniswap V3 pool and enable buying and selling as a result.

## ERC20z
ERC20z is an extension of the ERC20 standard by allowing an ERC20 token to have metadata.

The ERC20z contract also allows users to wrap and unwrap tokens. Wrapping converts a Zora 1155 token to an ERC20z token. Unwrap converts an ERC20z token to a Zora 1155 token.

## Royalties
Royalties contract manages royalty distribution from secondary markets on Uniswap V3. Creators can earn LP liquidity rewards from the Uniswap pool and can collect royalties using the Royalties contract.

## Deployment Determistic Addresses
- Zora Timed Sale Strategy: 0x777777722D078c97c6ad07d9f36801e653E356Ae
- Royalties: 0x77777771DF91C56c5468746E80DFA8b880f9719F
