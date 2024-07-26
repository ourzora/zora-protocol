import { defineConfig } from "@wagmi/cli";
import { Abi, zeroAddress } from "viem";
import { readdirSync, readFileSync } from "fs";
import * as abis from "@zoralabs/zora-1155-contracts";
import {
  zoraSparks1155ABI,
  zoraSparksManagerImplABI,
  sparksEthUnwrapperAndCallerABI,
  iUnwrapAndForwardActionABI,
  zoraMints1155ABI,
  zoraMintsManagerImplABI,
  sponsoredSparksSpenderABI,
  iSponsoredSparksSpenderActionABI,
} from "@zoralabs/sparks-contracts";
import { iPremintDefinitionsABI } from "@zoralabs/zora-1155-contracts";
import { zora, zoraSepolia } from "viem/chains";

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
      UPGRADE_GATE?: Address;
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
    addAddress({
      contractName: "UpgradeGate",
      chainId,
      address: jsonAddress.UPGRADE_GATE,
      abi: abis.upgradeGateABI,
    });
  }

  return addresses;
};

const getSparksAddresses = () => {
  const chainIds = [7777777, 999999999];

  const sparksProxyConfig = JSON.parse(
    readFileSync(
      "../sparks-deployments/deterministicConfig/sparksProxy/params.json",
      "utf-8",
    ),
  );

  const mintsProxyConfig = JSON.parse(
    readFileSync(
      "../sparks-deployments/deterministicConfig/mintsProxy/params.json",
      "utf-8",
    ),
  );

  const mintsEthUnwrapperAndCallerAddress = JSON.parse(
    readFileSync("../sparks-deployments/addresses/999999999.json", "utf-8"),
  ).MINTS_ETH_UNWRAPPER_AND_CALLER as Address;

  const sparksManagerAddress = sparksProxyConfig.manager
    .deployedAddress as Address;
  const zoraSparks1155Address = sparksProxyConfig.sparks1155
    .deployedAddress as Address;

  return {
    sparksManager: Object.fromEntries(
      chainIds.map((chainId) => [chainId, sparksManagerAddress]),
    ),
    sparks1155: Object.fromEntries(
      chainIds.map((chainId) => [chainId, zoraSparks1155Address as Address]),
    ),

    mintsEthUnwrapperAndCaller: Object.fromEntries(
      chainIds.map((chainId) => [chainId, mintsEthUnwrapperAndCallerAddress]),
    ),
    // deprecated mints contracts
    mintsManager: Object.fromEntries(
      chainIds.map((chainId) => [
        chainId,
        mintsProxyConfig.manager.deployedAddress as Address,
      ]),
    ),
    mints1155: Object.fromEntries(
      chainIds.map((chainId) => [
        chainId,
        mintsProxyConfig.mints1155.deployedAddress as Address,
      ]),
    ),
  };
};

const sparksAddresses = getSparksAddresses();

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
      abi: zoraSparksManagerImplABI,
      name: "ZoraSparksManagerImpl",
      address: sparksAddresses.sparksManager,
    },
    {
      abi: zoraSparks1155ABI,
      name: "ZoraSparks1155",
      address: sparksAddresses.sparks1155,
    },
    {
      abi: sparksEthUnwrapperAndCallerABI,
      name: "MintsEthUnwrapperAndCaller",
      address: sparksAddresses.mintsEthUnwrapperAndCaller,
    },
    {
      abi: iUnwrapAndForwardActionABI,
      name: "IUnwrapAndForwardAction",
    },
    // legacy mints contracts
    {
      abi: zoraMints1155ABI,
      name: "ZoraMints1155",
      address: sparksAddresses.mints1155,
    },
    {
      abi: zoraMintsManagerImplABI,
      name: "ZoraMintsManagerImpl",
      address: sparksAddresses.mintsManager,
    },
    // end legacy mints contract
    {
      abi: iPremintDefinitionsABI,
      name: "IPremintDefinitions",
    },
    {
      abi: sponsoredSparksSpenderABI,
      name: "SponsoredSparksSpender",
      address: {
        [zora.id]: "0x29b75AbA7dc7FE26d90CD96fbB390B26e04C4EB2",
      },
    },
    {
      abi: iSponsoredSparksSpenderActionABI,
      name: "ISponsoredSparksSpenderAction",
    },
  ],
});
