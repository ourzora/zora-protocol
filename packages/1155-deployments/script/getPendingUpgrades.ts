import { request, gql } from "graphql-request";
import {
  Address,
  Chain,
  Hex,
  PublicClient,
  createPublicClient,
  encodeFunctionData,
  http,
} from "viem";
import {
  zora,
  base,
  optimism,
  mainnet,
  zoraSepolia,
  arbitrum,
  blast,
  arbitrumSepolia,
  baseSepolia,
  sepolia,
} from "viem/chains";
import { getChain } from "@zoralabs/chains";
import { dirname, join } from "path";
import { fileURLToPath } from "url";
import { excludeVersionsToUpgrade } from "upgrades/config";
import {
  upgradeGateABI,
  zoraCreator1155FactoryImplABI,
  zoraCreator1155ImplABI,
} from "@zoralabs/zora-1155-contracts";
import { readFile, writeFile, readdir } from "fs/promises";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const CONFIG_BASE =
  "https://api.goldsky.com/api/public/project_clhk16b61ay9t49vm6ntn4mkz/subgraphs";

function getSubgraph(name: string, version: string): string {
  return `${CONFIG_BASE}/${name}/${version}/gn`;
}

const determinsticUpgradeGateAddress =
  "0xbC50029836A59A4E5e1Bb8988272F46ebA0F9900";

const chains: {
  chain: Chain;
  subgraph: string;
  upgradeGates: Address[];
  additionalVersions?: {
    [version: string]: Address | Address[];
  };
}[] = [
  {
    chain: zoraSepolia,
    upgradeGates: [determinsticUpgradeGateAddress],
    subgraph: getSubgraph("zora-create-zora-sepolia", "stable"),
  },
  {
    chain: mainnet,
    upgradeGates: [
      determinsticUpgradeGateAddress,
      "0xA6C5f2DE915240270DaC655152C3f6A91748cb85",
    ],
    subgraph: getSubgraph("zora-create-mainnet", "stable"),
    additionalVersions: {
      "1.3.0": "0x4c2b5f3b7eadadd58d5ec457abf57f4718b171ae",
      "1.4.0": "0xF62b0d56BA617F803DF1C464C519FF7D29451B2f",
    },
  },
  {
    chain: optimism,
    upgradeGates: [
      determinsticUpgradeGateAddress,
      "0x78b524931e9d847c40BcBf225c25e154a7B05fDA",
    ],
    subgraph: getSubgraph("zora-create-optimism", "stable"),
    additionalVersions: {
      "1.4.0": [
        "0x8Ca5e648C5dFEfcdDa06d627F4b490B719ccFD98",
        "0xeb29a4e5b84fef428c072deba2444e93c080ce87",
      ],
    },
  },
  {
    chain: base,
    upgradeGates: [
      determinsticUpgradeGateAddress,
      "0x9b24FD165a371042e5CA81e8d066d25CAD11EDE7",
    ],
    subgraph: getSubgraph("zora-create-base-mainnet", "stable"),
    additionalVersions: {
      "1.4.0": "0x805E0a08dE70f85C01F7848370d5e3fc08aAd0ea",
    },
  },
  {
    chain: zora,
    upgradeGates: [
      determinsticUpgradeGateAddress,
      "0x35ca784918bf11692708c1D530691704AAcEA95E",
    ],
    subgraph: getSubgraph("zora-create-zora-mainnet", "stable"),
    additionalVersions: {
      "1.4.0": "0x8Ca5e648C5dFEfcdDa06d627F4b490B719ccFD98",
    },
  },
  {
    chain: arbitrum,
    upgradeGates: [determinsticUpgradeGateAddress],
    subgraph: getSubgraph("zora-create-arbitrum-one", "stable"),
  },
  {
    chain: arbitrumSepolia,
    upgradeGates: [determinsticUpgradeGateAddress],
    subgraph: getSubgraph("zora-create-arbitrum-sepolia", "stable"),
  },
  {
    chain: sepolia,
    upgradeGates: [determinsticUpgradeGateAddress],
    subgraph: getSubgraph("zora-create-sepolia", "stable"),
  },

  {
    chain: baseSepolia,
    upgradeGates: [determinsticUpgradeGateAddress],
    subgraph: getSubgraph("zora-create-base-sepolia", "stable"),
  },
  {
    chain: blast,
    upgradeGates: [determinsticUpgradeGateAddress],
    subgraph: getSubgraph("zora-create-blast", "stable"),
  },
];

const getMissingUpgradesFrom = async ({
  toVersion,
  fromVersions,
  upgradeGate,
  publicClient,
}: {
  publicClient: PublicClient;
  toVersion: { version: string; contractImplAddress: Address };
  fromVersions: { version: string; contractImplAddress: Address }[];
  upgradeGate: Address;
}) =>
  (
    await Promise.all(
      fromVersions.map(async (fromVersion) => {
        if (fromVersion.version === toVersion.version) return;
        const upgradeRegistered = await publicClient.readContract({
          address: upgradeGate,
          abi: upgradeGateABI,
          functionName: "isRegisteredUpgradePath",
          args: [
            fromVersion.contractImplAddress,
            toVersion.contractImplAddress,
          ],
        });

        if (!upgradeRegistered) {
          return {
            address: fromVersion.contractImplAddress,
            version: fromVersion.version,
          };
        }
      }),
    )
  ).filter((x) => x) as { address: Address; version: string }[];

const getMissingUpgradePaths = async ({
  publicClient,
  upgradeGate,
  deployedVersions,
  targetVersion,
}: {
  publicClient: PublicClient;
  upgradeGate: Address;
  deployedVersions: { version: string; contractImplAddress: Address }[];
  targetVersion: { version: string; contractImplAddress: Address };
}) => {
  // filter versions to upgrade from by excluding versions that should not be upgraded
  const fromVersionImpls = deployedVersions.filter(
    ({ version }) => !excludeVersionsToUpgrade.includes(version),
  );

  if (fromVersionImpls.length === 0) return [];

  return await getMissingUpgradesFrom({
    toVersion: targetVersion,
    fromVersions: fromVersionImpls,
    upgradeGate,
    publicClient,
  });
};

async function getVersions({
  publicClient,
  subgraphUrl,
  additionalVersions,
}: {
  publicClient: PublicClient;
  subgraphUrl: string;
  additionalVersions?: {
    [version: string]: Address | Address[];
  };
}) {
  // get upgrades of type 1155

  const upgradeImpls = (
    (await request(
      subgraphUrl,
      gql`
        {
          upgrades(where: { type: "1155Factory" }) {
            impl
          }
        }
      `,
    )) as any
  ).upgrades.map((x: any) => x.impl);

  const deployedVersions = await Promise.all(
    upgradeImpls.map(async (factoryImpl: string) => {
      // read version from impl

      let version: string | null = null;
      try {
        version = await publicClient.readContract({
          address: factoryImpl as Address,
          abi: zoraCreator1155FactoryImplABI,
          functionName: "contractVersion",
        });
      } catch (e) {}

      let contractImpl: Address | null = null;

      // try to get contract for rpc
      try {
        contractImpl = await publicClient.readContract({
          address: factoryImpl as Address,
          abi: zoraCreator1155FactoryImplABI,
          functionName: "zora1155Impl",
        });
      } catch (e) {}

      return {
        version,
        contractImplAddress: contractImpl,
      };
    }),
  );

  if (additionalVersions) {
    await validateConfiguredVersions({ additionalVersions, publicClient });
    for (const [version, contractImplAddress] of Object.entries(
      additionalVersions,
    )) {
      const contractImplAddresses =
        typeof contractImplAddress === "string"
          ? [contractImplAddress]
          : contractImplAddress;
      contractImplAddresses.forEach((contractImplAddress) => {
        deployedVersions.push({
          version,
          contractImplAddress,
        });
      });
    }
  }

  return deployedVersions.filter((x) => x.version && x.contractImplAddress) as {
    version: string;
    contractImplAddress: Address;
  }[];
}

const makePublicClient = ({ chain, rpc }: { chain: Chain; rpc: string }) =>
  createPublicClient({
    transport: http(),
    chain: {
      ...chain,
      rpcUrls: {
        default: {
          http: [rpc],
        },
        public: {
          http: [rpc],
        },
      },
    },
  });

async function validateConfiguredVersions({
  additionalVersions,
  publicClient,
}: {
  additionalVersions: { [version: string]: Address | Address[] };
  publicClient: PublicClient;
}) {
  await Promise.all(
    Object.entries(additionalVersions).map(
      async ([version, contractImplAddressOrAddresses]) => {
        const contractImplAddresses =
          typeof contractImplAddressOrAddresses === "string"
            ? [contractImplAddressOrAddresses]
            : contractImplAddressOrAddresses;
        contractImplAddresses.forEach(async (contractImplAddress) => {
          const existingVersion = await publicClient.readContract({
            address: contractImplAddress,
            abi: zoraCreator1155ImplABI,
            functionName: "contractVersion",
          });

          if (existingVersion !== version) {
            throw new Error(
              `version ${existingVersion} on contract at ${contractImplAddress} mismatched from configured version ${version}`,
            );
          }
        });
      },
    ),
  );
}

const getCurrentConfiguredVersion = async ({
  publicClient,
  chainId,
}: {
  publicClient: PublicClient;
  chainId: number;
}) => {
  const addressesConfig = JSON.parse(
    await readFile(join(__dirname, `../addresses/${chainId}.json`), "utf-8"),
  );

  const deployed1155Impl = addressesConfig.CONTRACT_1155_IMPL;

  const targetVersion = await publicClient.readContract({
    address: deployed1155Impl,
    abi: zoraCreator1155ImplABI,
    functionName: "contractVersion",
  });

  return {
    version: targetVersion,
    contractImplAddress: deployed1155Impl,
  };
};

const saveVersions = async ({
  chainId,
  deployedVersions,
  targetVersion,
  missingUpgradePaths,
}: {
  chainId: number;
  deployedVersions: {
    version: string;
    contractImplAddress: Address;
  }[];
  targetVersion: {
    version: string;
    contractImplAddress: Address;
  };
  missingUpgradePaths: MissingUpgradePaths;
}) => {
  // save versions to ../versions/${chainId}.json

  const versionsPath = join(__dirname, `../versions/${chainId}.json`);

  await writeFile(
    versionsPath,
    JSON.stringify(
      {
        deployedVersions,
        targetVersion,
        missingUpgradePaths,
        missingUpgradePathTargets: missingUpgradePaths.map(
          ({ upgradeCall }) => upgradeCall.address,
        ),
        missingUpgradePathCalls: missingUpgradePaths.map(
          ({ upgradeCall }) => upgradeCall.calldata,
        ),
      },
      null,
      2,
    ),
  );
};

type MissingUpgradePaths = {
  from: {
    address: Address;
    version: string;
  }[];
  to: {
    address: Address;
    version: string;
  };
  upgradeCall: {
    address: Address;
    calldata: Hex;
  };
}[];

const queryMissing = async ({
  deployedVersions,
  targetVersion,
  upgradeGates,
  publicClient,
}: {
  deployedVersions: {
    version: string;
    contractImplAddress: Address;
  }[];
  targetVersion: {
    version: string;
    contractImplAddress: Address;
  };
  upgradeGates: Address[];
  publicClient: PublicClient;
}) => {
  const result = await Promise.all(
    upgradeGates.map(async (upgradeGate) => {
      const missingUpgradePaths = await getMissingUpgradePaths({
        publicClient,
        upgradeGate,
        deployedVersions: deployedVersions,
        targetVersion,
      });

      if (missingUpgradePaths.length === 0) return;

      const baseImpls = missingUpgradePaths.map(
        ({ address }) => address,
      ) as Address[];
      const upgradeImpl = targetVersion.contractImplAddress;

      const upgradeCallData = encodeFunctionData({
        abi: upgradeGateABI,
        functionName: "registerUpgradePath",
        args: [baseImpls, upgradeImpl],
      });

      return {
        from: missingUpgradePaths,
        to: {
          version: targetVersion.version,
          address: targetVersion.contractImplAddress,
        },
        upgradeCall: {
          address: upgradeGate,
          calldata: upgradeCallData,
        },
      };
    }),
  );

  return result.filter((x) => x) as MissingUpgradePaths;
};

const getMissingUpgradePathsForChain = async ({
  chain,
  rpc,
  subgraphUrl,
  upgradeGates,
  additionalVersions,
}: {
  chain: Chain;
  rpc: string;
  subgraphUrl: string;
  upgradeGates: Address[];
  additionalVersions?: {
    [version: string]: Address | Address[];
  };
}) => {
  const publicClient = makePublicClient({ chain, rpc });

  const deployedVersions = await getVersions({
    publicClient,
    subgraphUrl,
    additionalVersions,
  });

  const targetVersion = await getCurrentConfiguredVersion({
    publicClient,
    chainId: chain.id,
  });

  const missingUpgradePaths = await queryMissing({
    deployedVersions,
    targetVersion,
    upgradeGates,
    publicClient,
  });

  return {
    missingUpgradePaths,
    deployedVersions,
    targetVersion,
  };
};

async function getMissingUpgradePath(chainName: string) {
  const configuredChain =
    chainName === zoraSepolia.name || chainName === `${zoraSepolia.id}`
      ? {...zoraSepolia, rpcUrl: 'https://sepolia.rpc.zora.energy/'}
      : await getChain(chainName);

  console.log("Getting upgrade path updates for ", configuredChain.id);

  if (!configuredChain) {
    throw new Error(`No chain config found for chain name ${chainName}`);
  }

  const chainConfig = chains.find((x) => x.chain.id === configuredChain.id);

  if (!chainConfig) {
    throw new Error(
      `No chain config found for chain id ${configuredChain.id} (attempting to find ${chainName})`,
    );
  }

  const {
    chain,
    subgraph: subgraphUrl,
    upgradeGates,
    additionalVersions,
  } = chainConfig;

  const { missingUpgradePaths, deployedVersions, targetVersion } =
    await getMissingUpgradePathsForChain({
      chain,
      rpc: configuredChain.rpcUrl,
      subgraphUrl,
      upgradeGates,
      additionalVersions,
    });

  await saveVersions({
    chainId: chain.id,
    targetVersion,
    deployedVersions,
    missingUpgradePaths,
  });
}

export const main = async () => {
  // parse chain id as first argument:
  const chainName = process.argv[2];

  if (chainName) {
    await getMissingUpgradePath(chainName);
  } else {
    for (const file of await readdir(join(__dirname, "../addresses"))) {
      console.log(file);
      if (!file.endsWith(".json")) {
        continue;
      }
      try {
        await getMissingUpgradePath(file.replace(/.json$/, ""));
      } catch (err: any) {
        console.error(err);
      }
    }
  }
};

main();
