import {
  zoraCreator1155FactoryImplABI,
  zoraCreator1155FactoryImplAddress,
  zoraCreator1155ImplABI,
} from "@zoralabs/protocol-deployments";
import type {
  Account,
  Address,
  Chain,
  Hex,
  PublicClient,
  Transport,
  TransactionReceipt,
} from "viem";
import { decodeEventLog } from "viem";
import { makeContractParameters } from "src/utils";
import {
  getDeterministicContractAddress,
  getNewContractMintFee,
  new1155ContractVersion,
} from "./contract-setup";
import {
  CreateNew1155ContractAndTokenReturn,
  CreateNew1155ContractParams,
  CreateNew1155ParamsBase,
  CreateNew1155TokenParams,
  CreateNew1155TokenReturn,
  PrepareCreateReturn,
  NewContractParams,
} from "./types";
import { constructCreate1155TokenCalls } from "./token-setup";
import { makeOnchainPrepareMintFromCreate } from "./mint-from-create";
import { IContractGetter, SubgraphContractGetter } from "./contract-getter";

// Default royalty bps
const ROYALTY_BPS_DEFAULT = 1000;

export const getTokenIdFromCreateReceipt = (
  receipt: TransactionReceipt,
): bigint => {
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

  throw new Error(
    "No event found in receipt that could be used to get tokenId",
  );
};

export const getContractAddressFromReceipt = (
  receipt: TransactionReceipt,
): Address => {
  for (const data of receipt.logs) {
    try {
      const decodedLog = decodeEventLog({
        abi: zoraCreator1155FactoryImplABI,
        eventName: "SetupNewContract",
        ...data,
      });
      if (decodedLog && decodedLog.eventName === "SetupNewContract") {
        return decodedLog.args.newContract;
      }
    } catch (err: any) {}
  }

  throw new Error(
    "No event found in receipt that could be used to get contract address",
  );
};

type MakeContractParametersBase = {
  account: Address | Account;

  tokenSetupActions: Hex[];
};

export function makeCreateContractAndTokenCall({
  account,
  contract,
  royaltyBPS,
  fundsRecipient,
  tokenSetupActions,
  chainId,
}: {
  chainId: number;
  contract: NewContractParams;
  royaltyBPS?: number;
  fundsRecipient?: Address;
} & MakeContractParametersBase) {
  const accountAddress =
    typeof account === "string" ? account : account.address;
  return makeContractParameters({
    abi: zoraCreator1155FactoryImplABI,
    functionName: "createContractDeterministic",
    account,
    address:
      zoraCreator1155FactoryImplAddress[
        chainId as keyof typeof zoraCreator1155FactoryImplAddress
      ],
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

export function makeCreateTokenCall({
  contractAddress,
  account,
  tokenSetupActions,
}: {
  contractAddress: Address;
} & MakeContractParametersBase) {
  return makeContractParameters({
    abi: zoraCreator1155ImplABI,
    functionName: "multicall",
    account,
    address: contractAddress,
    args: [tokenSetupActions],
  });
}

/**
 * @deprecated Please use functions directly without creating a client.
 * Example: Instead of `new Create1155Client().createNew1155()`, use `createNew1155()`
 * Import the functions you need directly from their respective modules:
 * import { createNew1155, createNew1155OnExistingContract } from '@zoralabs/protocol-sdk'
 */
export class Create1155Client {
  private readonly publicClient: Pick<
    PublicClient<Transport, Chain>,
    "readContract" | "chain"
  >;
  public readonly contractGetter: IContractGetter;

  constructor({
    publicClient,
    contractGetter,
  }: {
    publicClient: Pick<
      PublicClient<Transport, Chain>,
      "readContract" | "chain"
    >;
    contractGetter: IContractGetter;
  }) {
    this.publicClient = publicClient;
    this.contractGetter = contractGetter;
  }

  async createNew1155(
    props: CreateNew1155ContractParams,
  ): Promise<CreateNew1155ContractAndTokenReturn> {
    return create1155({
      ...props,
      publicClient: this.publicClient,
    });
  }

  async createNew1155OnExistingContract({
    contractAddress: contract,
    account,
    token,
    getAdditionalSetupActions,
  }: CreateNew1155TokenParams): Promise<CreateNew1155TokenReturn> {
    return createNew1155Token({
      contractAddress: contract,
      account,
      token,
      getAdditionalSetupActions,
      contractGetter: this.contractGetter,
      chainId: this.publicClient.chain.id,
    });
  }
}

export async function create1155({
  contract,
  account,
  token,
  publicClient,
  getAdditionalSetupActions,
}: CreateNew1155ContractParams & {
  publicClient: Pick<PublicClient<Transport, Chain>, "readContract" | "chain">;
}): Promise<CreateNew1155ContractAndTokenReturn> {
  const nextTokenId = 1n;
  const chainId = publicClient.chain.id;
  const contractVersion = new1155ContractVersion(chainId);

  const result = prepareNew1155ContractAndToken({
    contract,
    account,
    chainId,
    token,
    getAdditionalSetupActions,
    nextTokenId,
    contractVersion,
  });

  const contractAddress = await getDeterministicContractAddress({
    account: typeof account === "string" ? account : account.address,
    publicClient,
    setupActions: result.setupActions,
    contract,
  });

  const prepareMint = makeOnchainPrepareMintFromCreate({
    contractAddress,
    contractVersion,
    minter: result.minter,
    result: result.newToken.salesConfig,
    tokenId: nextTokenId,
    chainId,
    // to get the contract wide mint fee, we get what it would be for a new contract
    getContractMintFee: async () =>
      getNewContractMintFee({
        publicClient,
        chainId,
      }),
  });

  return {
    ...result,
    prepareMint,
    contractAddress,
    contractVersion,
    newTokenId: nextTokenId,
  };
}

function prepareNew1155ContractAndToken({
  account,
  chainId,
  token,
  getAdditionalSetupActions,
  nextTokenId,
  contractVersion,
  contract,
}: CreateNew1155ContractParams & {
  chainId: number;
  nextTokenId: bigint;
  contractVersion: string;
}): PrepareCreateReturn {
  const { minter, newToken, setupActions } = prepareSetupActions({
    chainId,
    account,
    contractVersion: contractVersion,
    nextTokenId: nextTokenId,
    token,
    getAdditionalSetupActions,
    contractName: contract.name,
  });

  const request = makeCreateContractAndTokenCall({
    contract,
    account,
    chainId,
    tokenSetupActions: setupActions,
    fundsRecipient: token.payoutRecipient,
    royaltyBPS: token.royaltyBPS,
  });

  return {
    parameters: request,
    setupActions,
    newToken,
    minter,
  };
}

function prepareNew1155Token({
  contractAddress,
  account,
  getAdditionalSetupActions,
  token,
  chainId,
  nextTokenId,
  contractVersion,
  contractName,
}: Omit<CreateNew1155TokenParams, "contractGetter"> & {
  chainId: number;
  nextTokenId: bigint;
  contractVersion: string;
  contractName: string;
}): PrepareCreateReturn {
  const {
    minter,
    newToken,
    setupActions: tokenSetupActions,
  } = prepareSetupActions({
    chainId,
    account,
    contractVersion,
    nextTokenId,
    token,
    getAdditionalSetupActions,
    contractName,
  });

  const request = makeCreateTokenCall({
    contractAddress,
    account,
    tokenSetupActions,
  });

  return {
    parameters: request,
    setupActions: tokenSetupActions,
    newToken,
    minter,
  };
}

export async function createNew1155Token({
  contractAddress,
  account,
  getAdditionalSetupActions,
  token,
  chainId,
  contractGetter,
}: CreateNew1155TokenParams & {
  chainId: number;
  contractGetter?: IContractGetter;
}): Promise<CreateNew1155TokenReturn> {
  const contractGetterOrDefault =
    contractGetter ?? new SubgraphContractGetter(chainId);
  const { nextTokenId, contractVersion, mintFee, name } =
    await contractGetterOrDefault.getContractInfo({
      contractAddress,
      retries: 5,
    });

  const preparedToken = prepareNew1155Token({
    contractAddress,
    account,
    getAdditionalSetupActions,
    token,
    chainId,
    nextTokenId,
    contractVersion,
    contractName: name,
  });

  const prepareMint = makeOnchainPrepareMintFromCreate({
    contractAddress: contractAddress,
    contractVersion,
    minter: preparedToken.minter,
    result: preparedToken.newToken.salesConfig,
    tokenId: nextTokenId,
    getContractMintFee: async () => mintFee,
    chainId,
  });

  return {
    ...preparedToken,
    prepareMint,
    newTokenId: nextTokenId,
    contractVersion,
  };
}

export function prepareSetupActions({
  chainId,
  account,
  contractVersion,
  nextTokenId,
  token,
  contractName,
  getAdditionalSetupActions,
}: {
  chainId: number;
  contractVersion: string;
  nextTokenId: bigint;
  contractName: string;
} & CreateNew1155ParamsBase) {
  const {
    minter,
    newToken,
    setupActions: tokenSetupActions,
  } = constructCreate1155TokenCalls({
    chainId: chainId,
    ownerAddress: typeof account === "string" ? account : account.address,
    contractVersion,
    nextTokenId,
    ...token,
    contractName,
  });

  const setupActions = getAdditionalSetupActions
    ? [
        ...getAdditionalSetupActions({
          tokenId: nextTokenId,
        }),
        ...tokenSetupActions,
      ]
    : tokenSetupActions;

  return { minter, newToken, setupActions };
}
