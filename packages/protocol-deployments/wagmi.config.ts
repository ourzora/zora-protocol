import { defineConfig } from "@wagmi/cli";
import { Abi } from "viem";
import { readdirSync, readFileSync } from "fs";
import * as abis from "@zoralabs/zora-1155-contracts";

type Address = `0x${string}`;

type Addresses = {
  [contractName: string]: {
    address: {
      [chainId: number]: Address;
    };
    abi: Abi;
  };
};

const getAddresses = () => {
  const addresses: Addresses = {};

  const addressesFiles = readdirSync("./addresses");

  const addAddress = ({
    contractName,
    chainId,
    address,
    abi,
  }: {
    contractName: string;
    chainId: number;
    address?: Address;
    abi: Abi;
  }) => {
    if (!address) return;
    if (!addresses[contractName]) {
      addresses[contractName] = {
        address: {},
        abi,
      };
    }

    addresses[contractName]!.address[chainId] = address;
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

    addAddress({
      contractName: "ZoraCreatorFixedPriceSaleStrategy",
      chainId,
      address: jsonAddress.FIXED_PRICE_SALE_STRATEGY,
      abi: abis.zoraCreatorFixedPriceSaleStrategyABI,
    });
    addAddress({
      contractName: "ZoraCreatorMerkleMinterStrategy",
      chainId,
      address: jsonAddress.MERKLE_MINT_SALE_STRATEGY,
      abi: abis.zoraCreatorMerkleMinterStrategyABI,
    });
    addAddress({
      contractName: "ZoraCreator1155FactoryImpl",
      chainId,
      address: jsonAddress.FACTORY_PROXY,
      abi: abis.zoraCreator1155FactoryImplABI,
    });
    addAddress({
      contractName: "ZoraCreatorRedeemMinterFactory",
      chainId,
      address: jsonAddress.REDEEM_MINTER_FACTORY,
      abi: abis.zoraCreatorRedeemMinterFactoryABI,
    });
    addAddress({
      contractName: "ZoraCreator1155PremintExecutorImpl",
      chainId,
      address: jsonAddress.PREMINTER_PROXY,
      abi: abis.zoraCreator1155PremintExecutorImplABI,
    }),
      addAddress({
        contractName: "IImmutableCreate2Factory",
        chainId,
        address: "0x0000000000FFe8B47B3e2130213B802212439497",
        abi: abis.iImmutableCreate2FactoryABI,
      });
  }

  return addresses;
};

export default defineConfig({
  out: "package/wagmiGenerated.ts",
  contracts: [
    ...Object.entries(getAddresses()).map(([contractName, addressConfig]) => ({
      abi: addressConfig.abi,
      address: addressConfig.address,
      name: contractName,
    })),
    {
      abi: abis.zoraCreator1155ImplABI,
      name: "ZoraCreator1155Impl",
    },
  ],
});
