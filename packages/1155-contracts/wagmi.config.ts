import { defineConfig } from "@wagmi/cli";
import { foundry } from "@wagmi/cli/plugins";
import { readdirSync, readFileSync } from "fs";

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

type Address = `0x${string}`;

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

type Addresses = {
  [key in ContractNames]?: {
    [chainId: number]: Address;
  };
};

const getAddresses = () => {
  const addresses: Addresses = {};

  const addressesFiles = readdirSync("./addresses");

  const addAddress = (
    contractName: ContractNames,
    chainId: number,
    address?: Address
  ) => {
    if (!address) return;
    if (!addresses[contractName]) {
      addresses[contractName] = {};
    }

    addresses[contractName]![chainId] = address;
  };

  for (const addressesFile of addressesFiles) {
    const jsonAddress = JSON.parse(
      readFileSync(`./addresses/${addressesFile}`, "utf-8")
    ) as {
      FIXED_PRICE_SALE_STRATEGY: Address;
      MERKLE_MINT_SALE_STRATEGY: Address;
      REDEEM_MINTER_FACTORY: Address;
      "1155_IMPL": Address;
      FACTORY_IMPL: Address;
      FACTORY_PROXY: Address;
      PREMINTER_PROXY?: Address;
    };

    const chainId = parseInt(addressesFile.split(".")[0]);

    addAddress(
      "ZoraCreatorFixedPriceSaleStrategy",
      chainId,
      jsonAddress.FIXED_PRICE_SALE_STRATEGY
    );
    addAddress(
      "ZoraCreatorMerkleMinterStrategy",
      chainId,
      jsonAddress.MERKLE_MINT_SALE_STRATEGY
    );
    addAddress(
      "ZoraCreator1155FactoryImpl",
      chainId,
      jsonAddress.FACTORY_PROXY
    );
    addAddress(
      "ZoraCreatorRedeemMinterFactory",
      chainId,
      jsonAddress.REDEEM_MINTER_FACTORY
    );
    addAddress(
      "ZoraCreator1155PremintExecutorImpl",
      chainId,
      jsonAddress.PREMINTER_PROXY
    ),
      addAddress(
        "IImmutableCreate2Factory",
        chainId,
        "0x0000000000FFe8B47B3e2130213B802212439497"
      );
  }

  return addresses;
};

export default defineConfig({
  out: "package/wagmiGenerated.ts",
  plugins: [
    foundry({
      deployments: getAddresses(),
      include: contractFilesToInclude.map(
        (contractName) => `${contractName}.json`
      ),
    }),
  ],
});
