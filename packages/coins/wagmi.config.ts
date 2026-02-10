import { defineConfig } from "@wagmi/cli";
import { foundry } from "@wagmi/cli/plugins";

export default defineConfig({
  out: "package/wagmiGenerated.ts",
  plugins: [
    foundry({
      forge: {
        build: false,
      },
      include: [
        "BaseCoin",
        "ContentCoin",
        "CreatorCoin",
        "ZoraFactoryImpl",
        "IUniswapV3Pool",
        "IPoolConfigEncoding",
        "IPermit2",
        "IPoolManager",
        "AutoSwapper",
        "BuySupplyWithV4SwapHook",
        "ZoraV4CoinHook",
        "IUniversalRouter"
      ].map((contractName) => `${contractName}.json`),
    }),
  ],
});
