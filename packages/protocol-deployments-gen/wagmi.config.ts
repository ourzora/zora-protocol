import { ContractConfig, defineConfig } from "@wagmi/cli";
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
  iwethABI,
  iSwapRouterABI,
  iUniswapV3PoolABI,
} from "@zoralabs/erc20z";
import {
  commentsImplABI,
  callerAndCommenterImplABI,
} from "@zoralabs/comments-contracts";
import { zoraAccountManagerImplABI } from "@zoralabs/smart-wallet-contracts";
import { iPremintDefinitionsABI } from "@zoralabs/zora-1155-contracts";
import {
  cointagFactoryImplABI,
  cointagImplABI,
} from "@zoralabs/cointags-contracts";

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

const extractErrors = (abi: Abi) => {
  return abi.filter((x) => x.type === "error");
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

const getSharedAddresses = () => {
  const addresses: Addresses = {};
  const addressesFiles = readdirSync("../shared-contracts/chainConfigs");

  const storedConfigs = addressesFiles.map((file) => {
    return {
      chainId: parseInt(file.split(".")[0]),
      config: JSON.parse(
        readFileSync(`../shared-contracts/chainConfigs/${file}`, "utf-8"),
      ) as {
        WETH: Address;
        UNISWAP_SWAP_ROUTER: Address;
      },
    };
  });

  addAddress({
    abi: iwethABI,
    addresses,
    configKey: "WETH",
    contractName: "WETH",
    storedConfigs,
  });

  addAddress({
    abi: iSwapRouterABI,
    addresses,
    configKey: "UNISWAP_SWAP_ROUTER",
    contractName: "UniswapV3SwapRouter",
    storedConfigs,
  });

  return [
    ...toConfig(addresses),
    {
      abi: iUniswapV3PoolABI,
      name: "IUniswapV3Pool",
    },
  ];
};

const getSparksAddresses = () => {
  const addresses: Addresses = {};
  const addressesFiles = readdirSync("../sparks/addresses");

  const storedConfigs = addressesFiles.map((file) => {
    return {
      chainId: parseInt(file.split(".")[0]),
      config: JSON.parse(
        readFileSync(`../sparks/addresses/${file}`, "utf-8"),
      ) as {
        SPARKS_MANAGER: Address;
        SPARKS_1155: Address;
        MINTS_MANAGER: Address;
        MINTS_1155: Address;
        SPARKS_MANAGER_IMPL: Address;
        SPONSORED_SPARKS_SPENDER: Address;
        MINTS_ETH_UNWRAPPER_AND_CALLER: Address;
      },
    };
  });

  addAddress({
    abi: zoraSparksManagerImplABI,
    addresses,
    configKey: "SPARKS_MANAGER",
    contractName: "ZoraSparksManagerImpl",
    storedConfigs,
  });

  addAddress({
    abi: zoraSparks1155ABI,
    addresses,
    contractName: "ZoraSparks1155",
    configKey: "SPARKS_1155",
    storedConfigs,
  });

  addAddress({
    abi: sparksEthUnwrapperAndCallerABI,
    addresses,
    configKey: "MINTS_ETH_UNWRAPPER_AND_CALLER",
    contractName: "MintsEthUnwrapperAndCaller",
    storedConfigs,
  });

  addAddress({
    abi: zoraMintsManagerImplABI,
    addresses,
    contractName: "ZoraMintsManagerImpl",
    configKey: "MINTS_MANAGER",
    storedConfigs,
  });

  addAddress({
    abi: zoraMints1155ABI,
    addresses,
    contractName: "ZoraMints1155",
    configKey: "MINTS_1155",
    storedConfigs,
  });

  addAddress({
    abi: sponsoredSparksSpenderABI,
    addresses,
    contractName: "SponsoredSparksSpender",
    configKey: "SPONSORED_SPARKS_SPENDER",
    storedConfigs,
  });

  return [
    ...toConfig(addresses),
    {
      abi: iUnwrapAndForwardActionABI,
      name: "IUnwrapAndForwardAction",
    },
    {
      abi: iSponsoredSparksSpenderActionABI,
      name: "ISponsoredSparksSpenderAction",
    },
  ];
};

const getSmartWalletContracts = () => {
  const addresses: Addresses = {};
  const addressesFiles = readdirSync("../smart-wallet/addresses");

  const storedConfigs = addressesFiles.map((file) => {
    return {
      chainId: parseInt(file.split(".")[0]),
      config: JSON.parse(
        readFileSync(`../smart-wallet/addresses/${file}`, "utf-8"),
      ) as {
        ZORA_ACCOUNT_MANAGER: Address;
      },
    };
  });

  addAddress({
    abi: zoraAccountManagerImplABI,
    addresses,
    contractName: "ZoraAccountManager",
    configKey: "ZORA_ACCOUNT_MANAGER",
    storedConfigs,
  });

  return toConfig(addresses);
};

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

const getCommentsContracts = (): ContractConfig[] => {
  const addresses: Addresses = {};

  const addressesFiles = readdirSync("../comments/addresses");

  const storedConfigs = addressesFiles.map((file) => {
    return {
      chainId: parseInt(file.split(".")[0]),
      config: JSON.parse(
        readFileSync(`../comments/addresses/${file}`, "utf-8"),
      ) as {
        COMMENTS: Address;
        CALLER_AND_COMMENTER: Address;
      },
    };
  });

  addAddress({
    abi: commentsImplABI,
    addresses,
    configKey: "COMMENTS",
    contractName: "Comments",
    storedConfigs,
  });

  addAddress({
    abi: [
      ...callerAndCommenterImplABI,
      ...extractErrors(zoraTimedSaleStrategyImplABI),
      ...extractErrors(abis.zoraCreator1155ImplABI),
      ...extractErrors(commentsImplABI),
    ],
    addresses,
    configKey: "CALLER_AND_COMMENTER",
    contractName: "CallerAndCommenter",
    storedConfigs,
  });

  return toConfig(addresses);
};

const getCointagsContracts = (): ContractConfig[] => {
  const addresses: Addresses = {};

  const addressesFiles = readdirSync("../cointags/addresses");

  const storedConfigs = addressesFiles.map((file) => {
    return {
      chainId: parseInt(file.split(".")[0]),
      config: JSON.parse(
        readFileSync(`../cointags/addresses/${file}`, "utf-8"),
      ) as {
        COINTAG_FACTORY: Address;
      },
    };
  });

  addAddress({
    abi: cointagFactoryImplABI,
    addresses,
    configKey: "COINTAG_FACTORY",
    contractName: "CointagFactory",
    storedConfigs,
  });

  return [
    ...toConfig(addresses),
    {
      abi: cointagImplABI,
      name: "Cointag",
    },
  ];
};

export default defineConfig({
  out: "./generated/wagmi.ts",
  contracts: [
    ...get1155Contracts(),
    ...getErc20zContracts(),
    ...getSharedAddresses(),
    ...getCommentsContracts(),
    ...getSparksAddresses(),
    ...getSmartWalletContracts(),
    ...getCointagsContracts(),
    {
      abi: iPremintDefinitionsABI,
      name: "IPremintDefinitions",
    },
  ],
});
