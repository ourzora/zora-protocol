import { defineConfig } from "@wagmi/cli";
import { foundry } from "@wagmi/cli/plugins";

export default defineConfig({
  out: "package/wagmiGenerated.ts",
  plugins: [
    foundry({
      deployments: {
        ZoraFactoryImpl: {
          84532: "0x777777751622c0d3258f214F9DF38E35BF45baF3",
          8453: "0x777777751622c0d3258f214F9DF38E35BF45baF3",
        },
      },
      forge: {
        build: false,
      },
      include: ["Coin", "ZoraFactoryImpl", "IUniswapV3Pool"].map(
        (contractName) => `${contractName}.json`,
      ),
    }),
  ],
});
