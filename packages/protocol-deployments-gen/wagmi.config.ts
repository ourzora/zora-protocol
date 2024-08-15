import { Config, ContractConfig, defineConfig } from "@wagmi/cli";
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
import {
  erc20ZABI,
  zoraTimedSaleStrategyImplABI,
  royaltiesABI,
  secondarySwapABI,
} from "@zoralabs/erc20z";
import { iPremintDefinitionsABI } from "@zoralabs/zora-1155-contracts";
import { zora } from "viem/chains";

type Address = `0x${string}`;

type Addresses = {
  [contractName: string]: {
    address: {
      [chainId: number]: Address;
    };
    abi: Abi;
  };
};

const timedSaleStrategyErrors = zoraTimedSaleStrategyImplABI.filter(
  (x) => x.type === "error",
);

const zora1155Errors = [
  ...abis.zoraCreator1155ImplABI.filter((x) => x.type === "error"),
  ...timedSaleStrategyErrors,
];

type AbiAndAddresses = {
  abi: Abi;
  address: Record<number, Address>;
};

const addAddress = <
  T extends Record<string, AbiAndAddresses>,
  K extends Record<string, Address>,
>({
  contractName,
  abi,
  addresses,
  storedConfigs,
  configKey,
}: {
  abi: Abi;
  contractName: string;
  configKey: keyof K;
  addresses: T;
  storedConfigs: {
    chainId: number;
    config: K;
  }[];
}) => {
  // @ts-ignore
  addresses[contractName] = {
    address: {},
    abi,
  };

  for (const storedConfig of storedConfigs) {
    const address = storedConfig.config[configKey] as Address | undefined;
    if (address && address !== zeroAddress)
      addresses[contractName]!.address[storedConfig.chainId] = address;
  }
};

const toConfig = (
  addresses: Record<string, AbiAndAddresses>,
): ContractConfig[] => {
  return Object.entries(addresses).map(([contractName, config]) => ({
    abi: config.abi,
    name: contractName,
    address: config.address,
  }));
};

const get1155Contracts = (): ContractConfig[] => {
  const addresses: Addresses = {};

  const addressesFiles = readdirSync("../1155-deployments/addresses");

  const protocolRewardsConfig = JSON.parse(
    readFileSync("../protocol-rewards/deterministicConfig.json", "utf-8"),
  ) as {
    expectedAddress: Address;
  };

  const storedConfigs = addressesFiles.map((file) => {
    const protocolRewardsAddress = protocolRewardsConfig.expectedAddress;
    return {
      chainId: parseInt(file.split(".")[0]),
      config: {
        ...(JSON.parse(
          readFileSync(`../1155-deployments/addresses/${file}`, "utf-8"),
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
        }),
        PROTOCOL_REWARDS: protocolRewardsAddress,
      },
    };
  });

  addAddress({
    contractName: "ZoraCreatorFixedPriceSaleStrategy",
    abi: abis.zoraCreatorFixedPriceSaleStrategyABI,
    addresses,
    configKey: "FIXED_PRICE_SALE_STRATEGY",
    storedConfigs: storedConfigs,
  });
  addAddress({
    contractName: "ZoraCreatorMerkleMinterStrategy",
    abi: abis.zoraCreatorMerkleMinterStrategyABI,
    configKey: "MERKLE_MINT_SALE_STRATEGY",
    addresses,
    storedConfigs: storedConfigs,
  });
  addAddress({
    contractName: "ZoraCreator1155FactoryImpl",
    configKey: "FACTORY_PROXY",
    abi: [...abis.zoraCreator1155FactoryImplABI, ...zora1155Errors],
    addresses,
    storedConfigs,
  });
  addAddress({
    contractName: "ZoraCreatorRedeemMinterFactory",
    configKey: "REDEEM_MINTER_FACTORY",
    abi: abis.zoraCreatorRedeemMinterFactoryABI,
    addresses,
    storedConfigs,
  });
  addAddress({
    contractName: "ZoraCreator1155PremintExecutorImpl",
    configKey: "PREMINTER_PROXY",
    abi: abis.zoraCreator1155PremintExecutorImplABI,
    addresses,
    storedConfigs,
  });
  addAddress({
    contractName: "ProtocolRewards",
    configKey: "PROTOCOL_REWARDS",
    abi: abis.protocolRewardsABI,
    addresses,
    storedConfigs,
  });
  addAddress({
    contractName: "ERC20Minter",
    configKey: "ERC20_MINTER",
    abi: abis.erc20MinterABI,
    addresses,
    storedConfigs,
  });
  addAddress({
    contractName: "UpgradeGate",
    configKey: "UPGRADE_GATE",
    abi: abis.upgradeGateABI,
    addresses,
    storedConfigs,
  });

  return [
    ...toConfig(addresses),
    {
      abi: [...abis.zoraCreator1155ImplABI, ...timedSaleStrategyErrors],
      name: "ZoraCreator1155Impl",
    },
  ];
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

const getErc20zContracts = (): ContractConfig[] => {
  const addresses: Addresses = {};

  const addressesFiles = readdirSync("../erc20z/addresses");

  const storedConfigs = addressesFiles.map((file) => {
    return {
      chainId: parseInt(file.split(".")[0]),
      config: {
        ...(JSON.parse(
          readFileSync(`../erc20z/addresses/${file}`, "utf-8"),
        ) as {
          SWAP_HELPER: Address;
          ERC20Z: Address;
          NONFUNGIBLE_POSITION_MANAGER: Address;
          ROYALTIES: Address;
          SALE_STRATEGY: Address;
          SALE_STRATEGY_IMPL: Address;
          WETH: Address;
        }),
      },
    };
  });

  addAddress({
    abi: royaltiesABI,
    addresses,
    configKey: "ROYALTIES",
    contractName: "ERC20ZRoyalties",
    storedConfigs,
  });

  addAddress({
    abi: zoraTimedSaleStrategyImplABI,
    addresses,
    configKey: "SALE_STRATEGY",
    contractName: "zoraTimedSaleStrategy",
    storedConfigs,
  });

  addAddress({
    abi: secondarySwapABI,
    addresses,
    configKey: "SWAP_HELPER",
    contractName: "SecondarySwap",
    storedConfigs,
  });

  return [
    ...toConfig(addresses),
    {
      abi: erc20ZABI,
      name: "ERC20Z",
    },
  ];
};

export default defineConfig({
  out: "../protocol-deployments/src/generated/wagmi.ts",
  contracts: [
    ...get1155Contracts(),
    ...getErc20zContracts(),
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
