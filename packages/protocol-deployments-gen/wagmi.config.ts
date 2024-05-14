import { defineConfig } from "@wagmi/cli";
import { Abi, zeroAddress } from "viem";
import { readdirSync, readFileSync } from "fs";
import * as abis from "@zoralabs/zora-1155-contracts";
import {
  zoraMints1155ABI,
  zoraMintsManagerImplABI,
  mintsEthUnwrapperAndCallerABI,
  iUnwrapAndForwardActionABI,
} from "@zoralabs/mints-contracts";

type Address = `0x${string}`;

type Addresses = {
  [contractName: string]: {
    address: {
      [chainId: number]: Address;
    };
    abi: Abi;
  };
};

const get1155Addresses = () => {
  const addresses: Addresses = {};

  const addressesFiles = readdirSync("../1155-deployments/addresses");

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
    if (!address || address === zeroAddress) return;
    if (!addresses[contractName]) {
      addresses[contractName] = {
        address: {},
        abi,
      };
    }

    addresses[contractName]!.address[chainId] = address;
  };

  const protocolRewardsConfig = JSON.parse(
    readFileSync("../protocol-rewards/deterministicConfig.json", "utf-8"),
  ) as {
    expectedAddress: Address;
  };

  for (const addressesFile of addressesFiles) {
    const jsonAddress = JSON.parse(
      readFileSync(`../1155-deployments/addresses/${addressesFile}`, "utf-8"),
    ) as {
      FIXED_PRICE_SALE_STRATEGY: Address;
      MERKLE_MINT_SALE_STRATEGY: Address;
      REDEEM_MINTER_FACTORY: Address;
      "1155_IMPL": Address;
      FACTORY_IMPL: Address;
      FACTORY_PROXY: Address;
      PREMINTER_PROXY?: Address;
      ERC20_MINTER?: Address;
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
    });
    addAddress({
      contractName: "ProtocolRewards",
      chainId,
      address: protocolRewardsConfig.expectedAddress,
      abi: abis.protocolRewardsABI,
    });
    addAddress({
      contractName: "ERC20Minter",
      chainId,
      abi: abis.erc20MinterABI,
      address: jsonAddress.ERC20_MINTER,
    });
  }

  return addresses;
};

const getMintsAddresses = () => {
  const addressesFiles = readdirSync("../mints-deployments/addresses");

  const chainIds = addressesFiles.map((x) => Number(x.split(".")[0]));

  const mintsProxyConfig = JSON.parse(
    readFileSync(
      "../mints-deployments/deterministicConfig/mintsProxy/params.json",
      "utf-8",
    ),
  );

  const mintsEthUnwrapperAndCallerAddress = JSON.parse(
    readFileSync("../mints-deployments/addresses/999999999.json", "utf-8"),
  ).MINTS_ETH_UNWRAPPER_AND_CALLER as Address;

  const mintsManagerAddress = mintsProxyConfig.manager
    .deployedAddress as Address;
  const zoraMints1155Address = mintsProxyConfig.mints1155
    .deployedAddress as Address;

  return {
    mintsManager: Object.fromEntries(
      chainIds.map((chainId) => [chainId, mintsManagerAddress]),
    ),
    mints1155: Object.fromEntries(
      chainIds.map((chainId) => [chainId, zoraMints1155Address as Address]),
    ),
    mintsEthUnwrapperAndCaller: Object.fromEntries(
      chainIds.map((chainId) => [chainId, mintsEthUnwrapperAndCallerAddress]),
    ),
  };
};

const mintsAddresses = getMintsAddresses();

export default defineConfig({
  out: "../protocol-deployments/src/generated/wagmi.ts",
  contracts: [
    ...Object.entries(get1155Addresses()).map(
      ([contractName, addressConfig]) => ({
        abi: addressConfig.abi,
        address: addressConfig.address,
        name: contractName,
      }),
    ),
    {
      abi: abis.zoraCreator1155ImplABI,
      name: "ZoraCreator1155Impl",
    },
    {
      abi: zoraMintsManagerImplABI,
      name: "ZoraMintsManagerImpl",
      address: mintsAddresses.mintsManager,
    },
    {
      abi: zoraMints1155ABI,
      name: "ZoraMints1155",
      address: mintsAddresses.mints1155,
    },
    {
      abi: mintsEthUnwrapperAndCallerABI,
      name: "MintsEthUnwrapperAndCaller",
      address: mintsAddresses.mintsEthUnwrapperAndCaller,
    },
    {
      abi: iUnwrapAndForwardActionABI,
      name: "IUnwrapAndForwardAction",
    },
  ],
});
