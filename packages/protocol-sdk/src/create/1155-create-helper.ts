import {
  zoraCreator1155FactoryImplABI,
  zoraCreator1155FactoryImplAddress,
  zoraCreator1155ImplABI,
} from "@zoralabs/protocol-deployments";
import type {
  Account,
  Address,
  Hex,
  SimulateContractParameters,
  TransactionReceipt,
} from "viem";
import { decodeEventLog } from "viem";
import { makeContractParameters, ClientConfig, setupClient } from "src/utils";
import { getContractInfo } from "./contract-setup";
import { ContractType, CreateNew1155Params, New1155Token } from "./types";
import { constructCreate1155TokenCalls } from "./token-setup";

// Default royalty bps
const ROYALTY_BPS_DEFAULT = 1000;

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

type CreateNew1155TokenReturn = {
  parameters: SimulateContractParameters<
    any,
    any,
    any,
    any,
    any,
    Account | Address
  >;
  tokenSetupActions: Hex[];
  collectionAddress: Address;
  newTokenId: bigint;
  newToken: New1155Token;
  minter: Address;
  contractExists: boolean;
};

function makeCreateContractAndTokenCall({
  contractExists,
  contractAddress,
  contract,
  account,
  royaltyBPS,
  tokenSetupActions,
  fundsRecipient,
}: {
  contractExists: boolean;
  contractAddress: Address;
  contract: ContractType;
  account: Address | Account;
  royaltyBPS?: number;
  fundsRecipient?: Address;
  tokenSetupActions: Hex[];
}) {
  if (!contractAddress && typeof contract === "string") {
    throw new Error("Invariant: contract cannot be missing and an address");
  }

  if (!contractExists) {
    if (typeof contract === "string") {
      throw new Error("Invariant: expected contract object");
    }

    const accountAddress =
      typeof account === "string" ? account : account.address;
    return makeContractParameters({
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
          royaltyBPS: royaltyBPS || ROYALTY_BPS_DEFAULT,
          royaltyRecipient: fundsRecipient || accountAddress,
        },
        contract.defaultAdmin || accountAddress,
        tokenSetupActions,
      ],
    });
  }

  return makeContractParameters({
    abi: zoraCreator1155ImplABI,
    functionName: "multicall",
    account,
    address: contractAddress,
    args: [tokenSetupActions],
  });
}

export function create1155CreatorClient(clientConfig: ClientConfig) {
  const { publicClient, chain } = setupClient(clientConfig);
  async function createNew1155Token({
    contract,
    account,
    getAdditionalSetupActions,
    token: tokenConfig,
  }: CreateNew1155Params): Promise<CreateNew1155TokenReturn> {
    const { contractExists, contractAddress, nextTokenId, contractVersion } =
      await getContractInfo({
        publicClient,
        chainId: chain.id,
        contract,
        account,
      });

    const {
      minter,
      newToken,
      setupActions: tokenSetupActions,
    } = constructCreate1155TokenCalls({
      chainId: chain.id,
      ownerAddress: account,
      contractVersion,
      nextTokenId,
      ...tokenConfig,
    });

    const setupActions = getAdditionalSetupActions
      ? [
          ...getAdditionalSetupActions({
            tokenId: nextTokenId,
            contractAddress,
          }),
          ...tokenSetupActions,
        ]
      : tokenSetupActions;

    const request = makeCreateContractAndTokenCall({
      contractExists,
      contractAddress,
      contract,
      account,
      tokenSetupActions: setupActions,
      royaltyBPS: tokenConfig.royaltyBPS,
      fundsRecipient: tokenConfig.payoutRecipient,
    });

    return {
      parameters: request,
      tokenSetupActions,
      collectionAddress: contractAddress,
      contractExists,
      newTokenId: nextTokenId,
      newToken,
      minter,
    };
  }
  return { createNew1155Token };
}
