import { defineConfig } from "@wagmi/cli";
import { foundry } from "@wagmi/cli/plugins";

export default defineConfig({
  out: "package/wagmiGenerated.ts",
  plugins: [
    foundry({
      include: ["ISwapRouter", "IWETH", "IUniswapV3Pool", "IQuoterV2"].map(
        (contractName) => `${contractName}.json`,
      ),
    }),
  ],
});
