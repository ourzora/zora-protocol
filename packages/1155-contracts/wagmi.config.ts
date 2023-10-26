import { defineConfig } from "@wagmi/cli";
import { foundry } from "@wagmi/cli/plugins";

type ContractNames =
  | "ZoraCreator1155FactoryImpl"
  | "ZoraCreator1155Impl"
  | "ZoraCreatorFixedPriceSaleStrategy"
  | "ZoraCreatorMerkleMinterStrategy"
  | "ZoraCreatorRedeemMinterFactory"
  | "ZoraCreatorRedeemMinterStrategy"
  | "ZoraCreator1155PremintExecutorImpl"
  | "DeterministicProxyDeployer"
  | "IImmutableCreate2Factory";

const contractFilesToInclude: ContractNames[] = [
  "ZoraCreator1155FactoryImpl",
  "ZoraCreator1155Impl",
  "ZoraCreatorFixedPriceSaleStrategy",
  "ZoraCreatorMerkleMinterStrategy",
  "ZoraCreatorRedeemMinterFactory",
  "ZoraCreatorRedeemMinterStrategy",
  "ZoraCreator1155PremintExecutorImpl",
  "DeterministicProxyDeployer",
  "IImmutableCreate2Factory",
];

export default defineConfig({
  out: "package/wagmiGenerated.ts",
  plugins: [
    foundry({
      forge: {
        build: false,
      },
      include: contractFilesToInclude.map(
        (contractName) => `${contractName}.json`
      ),
    }),
  ],
});
