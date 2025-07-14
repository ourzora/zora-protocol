import { defineConfig } from "@wagmi/cli";
import { foundry } from "@wagmi/cli/plugins";
import { abi as zoraMints1155Abi } from "./deprecatedAbis/zoraMints1155";
import { abi as zoraMintsManagerImplAbi } from "./deprecatedAbis/zoraMintsManagerImpl";

export default defineConfig({
  out: "package/wagmiGenerated.ts",
  plugins: [
    foundry({
      forge: {
        build: false,
      },
      include: [
        "ZoraSparks1155",
        "ZoraSparksManagerImpl",
        "SparksEthUnwrapperAndCaller",
        "IUnwrapAndForwardAction",
        "SponsoredSparksSpender",
        "ISponsoredSparksSpenderAction",
      ].map((contractName) => `${contractName}.json`),
    }),
  ],
  contracts: [
    {
      abi: zoraMints1155Abi,
      name: "ZoraMints1155",
    },
    {
      abi: zoraMintsManagerImplAbi,
      name: "ZoraMintsManagerImpl",
    },
  ],
});
