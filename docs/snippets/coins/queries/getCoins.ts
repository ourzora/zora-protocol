import { getCoins } from "@zoralabs/coins-sdk";
import { base } from "viem/chains";

export async function fetchMultipleCoins() {
  const response = await getCoins({
    coins: [
      {
        chainId: base.id,
        collectionAddress: "0xFirstCoinAddress",
      },
      {
        chainId: base.id,
        collectionAddress: "0xSecondCoinAddress",
      },
      {
        chainId: base.id,
        collectionAddress: "0xThirdCoinAddress",
      },
    ],
  });

  // Process each coin in the response
  response.data?.zora20Tokens?.forEach((coin: any, index: number) => {
    console.log(`Coin ${index + 1}: ${coin.name} (${coin.symbol})`);
    console.log(`- Market Cap: ${coin.marketCap}`);
    console.log(`- 24h Volume: ${coin.volume24h}`);
    console.log(`- Holders: ${coin.uniqueHolders}`);
    console.log("-----------------------------------");
  });

  return response;
}
