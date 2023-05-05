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
  | "ZoraCreatorSignatureMinterStrategy";

type Address = `0x${string}`;

const contractFilesToInclude: ContractNames[] = [
  "ZoraCreator1155FactoryImpl",
  "ZoraCreator1155Impl",
  "ZoraCreatorFixedPriceSaleStrategy",
  "ZoraCreatorMerkleMinterStrategy",
  "ZoraCreatorRedeemMinterFactory",
  "ZoraCreatorRedeemMinterStrategy",
  "ZoraCreatorSignatureMinterStrategy",
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
    address: Address
  ) => {
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
