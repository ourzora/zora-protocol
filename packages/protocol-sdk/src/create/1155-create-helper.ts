import {
  zoraCreator1155FactoryImplABI,
  zoraCreator1155FactoryImplAddress,
  zoraCreator1155ImplABI,
  zoraCreatorFixedPriceSaleStrategyABI,
} from "@zoralabs/protocol-deployments";
import type {
  Address,
  Hex,
  PublicClient,
  TransactionReceipt,
  WalletClient,
} from "viem";
import { decodeEventLog, encodeFunctionData, zeroAddress } from "viem";
import { OPEN_EDITION_MINT_SIZE } from "../constants";

const saleEndForever = 18446744073709551615n;
const royaltyBPSDefault = 1000;

type SalesConfigParamsType = {
  // defaults to 0
  pricePerToken?: bigint;
  // defaults to 0, in seconds
  saleStart?: bigint;
  // defaults to forever, in seconds
  saleEnd?: bigint;
  maxTokensPerAddress?: number;
  fundsRecipient?: Address;
};

export const DEFAULT_SALE_SETTINGS = {
  fundsRecipient: zeroAddress,
  pricePerToken: 0n,
  saleStart: 0n,
  saleEnd: saleEndForever,
  maxTokensPerAddress: 0n,
};
const PERMISSION_BIT_MINTER = 2n ** 2n;

type ContractType =
  | {
      name: string;
      uri: string;
      defaultAdmin?: Address;
    }
  | Address;

type RoyaltySettingsType = {
  royaltyBPS: number;
  royaltyRecipient: Address;
};

export function create1155TokenSetupArgs({
  nextTokenId,
  mintToCreatorCount,
  tokenMetadataURI,
  fixedPriceMinterAddress,
  createReferral,
  maxSupply,
  account,
  salesConfig,
  royaltySettings,
}: {
  maxSupply?: bigint | number;
  createReferral?: Address;
  nextTokenId: bigint;
  mintToCreatorCount: bigint | number;
  account: Address;
  tokenMetadataURI: string;
  fixedPriceMinterAddress: Address;
  salesConfig: SalesConfigParamsType;
  royaltySettings?: RoyaltySettingsType;
}) {
  if (!maxSupply) {
    maxSupply = OPEN_EDITION_MINT_SIZE;
  }
  maxSupply = BigInt(maxSupply);
  mintToCreatorCount = BigInt(mintToCreatorCount);

  const salesConfigWithDefaults = Object.assign(
    // Set static sales default.
    DEFAULT_SALE_SETTINGS,
    // Override with user settings.
    salesConfig,
  );

  const setupActions = [
    encodeFunctionData({
      abi: zoraCreator1155ImplABI,
      functionName: "addPermission",
      args: [0n, fixedPriceMinterAddress, PERMISSION_BIT_MINTER],
    }),
    encodeFunctionData({
      abi: zoraCreator1155ImplABI,
      functionName: "assumeLastTokenIdMatches",
      args: [nextTokenId - 1n],
    }),
    createReferral
      ? encodeFunctionData({
          abi: zoraCreator1155ImplABI,
          functionName: "setupNewTokenWithCreateReferral",
          args: [tokenMetadataURI, maxSupply, createReferral],
        })
      : encodeFunctionData({
          abi: zoraCreator1155ImplABI,
          functionName: "setupNewToken",
          args: [tokenMetadataURI, maxSupply],
        }),
    encodeFunctionData({
      abi: zoraCreator1155ImplABI,
      functionName: "callSale",
      args: [
        nextTokenId,
        fixedPriceMinterAddress,
        encodeFunctionData({
          abi: zoraCreatorFixedPriceSaleStrategyABI,
          functionName: "setSale",
          args: [nextTokenId, salesConfigWithDefaults],
        }),
      ],
    }),
  ];

  if (mintToCreatorCount) {
    setupActions.push(
      encodeFunctionData({
        abi: zoraCreator1155ImplABI,
        functionName: "adminMint",
        args: [account, nextTokenId, mintToCreatorCount, "0x"],
      }),
    );
  }

  if (royaltySettings) {
    setupActions.push(
      encodeFunctionData({
        abi: zoraCreator1155ImplABI,
        functionName: "updateRoyaltiesForToken",
        args: [
          nextTokenId,
          {
            royaltyMintSchedule: 0,
            royaltyBPS: royaltySettings?.royaltyBPS || royaltyBPSDefault,
            royaltyRecipient: royaltySettings?.royaltyRecipient || account,
          },
        ],
      }),
    );
  }

  return setupActions;
}

export const getTokenIdFromCreateReceipt = (
  receipt: TransactionReceipt,
): bigint | undefined => {
  for (const data of receipt.logs) {
    try {
      const decodedLog = decodeEventLog({
        abi: zoraCreator1155ImplABI,
        eventName: "SetupNewToken",
        ...data,
      });
      if (decodedLog && decodedLog.eventName === "SetupNewToken") {
        return decodedLog.args.tokenId;
      }
    } catch (err: any) {}
  }
};

async function getContractExists(
  publicClient: PublicClient,
  contract: ContractType,
  account: Address,
) {
  let contractAddress;
  let contractExists = false;
  if (typeof contract !== "string") {
    contractAddress = await publicClient.readContract({
      abi: zoraCreator1155FactoryImplABI,
      // Since this address is deterministic we can hardcode a chain id safely here.
      address: zoraCreator1155FactoryImplAddress[999],
      functionName: "deterministicContractAddress",
      args: [
        account,
        contract.uri,
        contract.name,
        contract.defaultAdmin || account,
      ],
    });
    try {
      await publicClient.readContract({
        abi: zoraCreator1155ImplABI,
        address: contractAddress,
        functionName: "contractVersion",
      });
      contractExists = true;
    } catch (e: any) {
      // This logic branch is hit if the contract doesn't exist
      //  falling back to contractExists to false.
    }
    return { contractAddress, contractExists };
  }

  return {
    contractExists: true,
    contractAddress: contract,
  };
}

export async function createNew1155Token({
  publicClient,
  contract,
  tokenMetadataURI,
  mintToCreatorCount = 1,
  salesConfig = {},
  maxSupply,
  account,
  royaltySettings,
  getAdditionalSetupActions,
}: {
  publicClient: PublicClient;
  account: Address;
  maxSupply?: bigint | number;
  royaltySettings?: RoyaltySettingsType;
  royaltyBPS?: number;
  contract: ContractType;
  tokenMetadataURI: string;
  mintToCreatorCount?: bigint | number;
  salesConfig?: SalesConfigParamsType;
  getAdditionalSetupActions?: (args: {
    tokenId: bigint;
    contractAddress: Address;
  }) => Hex[];
}) {
  const { contractExists, contractAddress } = await getContractExists(
    publicClient,
    contract,
    account,
  );

  let nextTokenId = 1n;

  if (contractExists) {
    nextTokenId = await publicClient.readContract({
      abi: zoraCreator1155ImplABI,
      functionName: "nextTokenId",
      address: contractAddress,
    });
  }

  const fixedPriceMinterAddress = await publicClient.readContract({
    abi: zoraCreator1155FactoryImplABI,
    address: zoraCreator1155FactoryImplAddress[999],
    functionName: "fixedPriceMinter",
  });

  let tokenSetupActions = create1155TokenSetupArgs({
    tokenMetadataURI,
    nextTokenId,
    salesConfig,
    maxSupply,
    fixedPriceMinterAddress,
    account,
    mintToCreatorCount,
    royaltySettings,
  });
  if (getAdditionalSetupActions) {
    tokenSetupActions = [
      ...getAdditionalSetupActions({ tokenId: nextTokenId, contractAddress }),
      ...tokenSetupActions,
    ];
  }

  if (!contractAddress && typeof contract === "string") {
    throw new Error("Invariant: contract cannot be missing and an address");
  }
  if (!contractExists && typeof contract !== "string") {
    const { request } = await publicClient.simulateContract({
      abi: zoraCreator1155FactoryImplABI,
      functionName: "createContractDeterministic",
      account,
      address: zoraCreator1155FactoryImplAddress[999],
      args: [
        contract.uri,
        contract.name,
        {
          // deprecated
          royaltyMintSchedule: 0,
          royaltyBPS: royaltySettings?.royaltyBPS || royaltyBPSDefault,
          royaltyRecipient: royaltySettings?.royaltyRecipient || account,
        },
        contract.defaultAdmin || account,
        tokenSetupActions,
      ],
    });
    return {
      send: (walletClient: WalletClient) => walletClient.writeContract(request),
      tokenSetupActions,
      contractAddress,
      contractExists,
    };
  } else if (contractExists) {
    const { request } = await publicClient.simulateContract({
      abi: zoraCreator1155ImplABI,
      functionName: "multicall",
      account,
      address: contractAddress,
      args: [tokenSetupActions],
    });
    return {
      send: (walletClient: WalletClient) => walletClient.writeContract(request),
      tokenSetupActions,
      contractAddress,
      contractExists,
    };
  }
  throw new Error("Unsupported contract argument type");
}
