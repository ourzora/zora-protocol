import { decodeEventLog, zeroAddress } from "viem";
import type {
  Account,
  Address,
  Chain,
  Hex,
  SimulateContractParameters,
  TransactionReceipt,
  TypedDataDefinition,
  WalletClient,
} from "viem";
import {
  encodePremintConfig,
  zoraCreator1155PremintExecutorImplABI,
} from "@zoralabs/protocol-deployments";
import {
  getPremintCollectionAddress,
  isValidSignature,
  isAuthorizedToCreatePremint,
  getPremintExecutorAddress,
  applyUpdateToPremint,
  makeNewPremint,
  supportsPremintVersion,
  getPremintMintCosts,
  makeMintRewardsRecipient,
  getDefaultFixedPriceMinterAddress,
  emptyContractCreationConfig,
  defaultAdditionalAdmins,
  toContractCreationConfigOrAddress,
} from "./preminter";
import {
  PremintConfigVersion,
  ContractCreationConfig,
  TokenConfigForVersion,
  TokenCreationConfigV1,
  TokenCreationConfigV2,
  TokenCreationConfig,
  PremintConfigForVersion,
  PremintConfigWithVersion,
  PremintMintArguments,
  premintTypedDataDefinition,
} from "@zoralabs/protocol-deployments";
import { PremintAPIClient } from "./premint-api-client";
import type { DecodeEventLogReturnType } from "viem";
import { OPEN_EDITION_MINT_SIZE } from "../constants";
import { IHttpClient } from "src/apis/http-api-base";
import { getApiNetworkConfigForChain } from "src/mint/mint-api-client";
import { MintCosts } from "src/mint/mint-client";
import {
  ClientConfig,
  makeSimulateContractParamaters,
  PublicClient,
  setupClient,
} from "src/utils";
import {
  ContractCreationConfigAndAddress,
  ContractCreationConfigOrAddress,
} from "./contract-types";

type PremintedV2LogType = DecodeEventLogReturnType<
  typeof zoraCreator1155PremintExecutorImplABI,
  "PremintedV2"
>["args"];

type URLSReturnType = {
  explorer: null | string;
  zoraCollect: null | string;
  zoraManage: null | string;
};

export const defaultTokenConfigV1MintArguments = (): Omit<
  TokenCreationConfigV1,
  "fixedPriceMinter" | "tokenURI" | "royaltyRecipient"
> => ({
  maxSupply: OPEN_EDITION_MINT_SIZE,
  maxTokensPerAddress: 0n,
  pricePerToken: 0n,
  mintDuration: BigInt(60 * 60 * 24 * 7), // 1 week
  mintStart: 0n,
  royaltyMintSchedule: 0,
  royaltyBPS: 1000, // 10%,
});

export const defaultTokenConfigV2MintArguments = (): Omit<
  TokenCreationConfigV2,
  "fixedPriceMinter" | "tokenURI" | "payoutRecipient" | "createReferral"
> => ({
  maxSupply: OPEN_EDITION_MINT_SIZE,
  maxTokensPerAddress: 0n,
  pricePerToken: 0n,
  mintDuration: BigInt(60 * 60 * 24 * 7), // 1 week
  mintStart: 0n,
  royaltyBPS: 1000, // 10%,
});

const makeTokenConfigWithDefaults = <T extends PremintConfigVersion>({
  chainId,
  premintConfigVersion,
  tokenCreationConfig,
  payoutRecipient,
}: {
  chainId: number;
  premintConfigVersion: T;
  tokenCreationConfig: Partial<TokenConfigForVersion<T>> & { tokenURI: string };
  payoutRecipient: Address;
}): TokenConfigForVersion<T> => {
  if (premintConfigVersion === PremintConfigVersion.V3) {
    throw new Error("PremintV3 not supported in SDK");
  }

  const fixedPriceMinter =
    (
      tokenCreationConfig as
        | Partial<TokenCreationConfigV1>
        | Partial<TokenCreationConfigV2>
    ).fixedPriceMinter || getDefaultFixedPriceMinterAddress(chainId);

  if (premintConfigVersion === PremintConfigVersion.V1) {
    return {
      fixedPriceMinter,
      ...defaultTokenConfigV1MintArguments(),
      royaltyRecipient: payoutRecipient,
      ...(tokenCreationConfig as Partial<TokenCreationConfigV1>),
    } as TokenCreationConfigV1;
  } else if (premintConfigVersion === PremintConfigVersion.V2) {
    return {
      fixedPriceMinter,
      ...defaultTokenConfigV2MintArguments(),
      payoutRecipient: payoutRecipient,
      createReferral: zeroAddress,
      ...tokenCreationConfig,
    };
  } else {
    throw new Error(`Invalid premint config version ${premintConfigVersion}`);
  }
};

/**
 * Gets the preminted log from receipt
 *
 * @param receipt Preminted log from receipt
 * @returns Premint event arguments
 */
export function getPremintedLogFromReceipt(
  receipt: TransactionReceipt,
): PremintedV2LogType | undefined {
  for (const data of receipt.logs) {
    try {
      const decodedLog = decodeEventLog({
        abi: zoraCreator1155PremintExecutorImplABI,
        eventName: "PremintedV2",
        ...data,
      });
      if (decodedLog.eventName === "PremintedV2") {
        return decodedLog.args;
      }
    } catch (err: any) {}
  }
}
/**
 * Preminter API to access ZORA Premint functionality.
 */
class PremintClient {
  readonly apiClient: PremintAPIClient;
  readonly publicClient: PublicClient;
  readonly chain: Chain;

  constructor(
    chain: Chain,
    publicClient: PublicClient,
    httpClient: IHttpClient,
  ) {
    this.chain = chain;
    this.apiClient = new PremintAPIClient(chain.id, httpClient);
    this.publicClient = publicClient;
  }

  getDataFromPremintReceipt(receipt: TransactionReceipt) {
    const premintedLog = getPremintedLogFromReceipt(receipt);
    return {
      premintedLog,
      urls: this.makeUrls({
        address: premintedLog?.contractAddress,
        tokenId: premintedLog?.tokenId,
      }),
    };
  }

  /**
   * Prepares data for updating a premint
   *
   * @param parameters - Parameters for updating the premint {@link UpdatePremintParams}
   * @returns A PremintReturn. {@link PremintReturn}
   */
  async updatePremint(args: UpdatePremintParams): Promise<PremintReturn<any>> {
    return await updatePremint({
      ...args,
      apiClient: this.apiClient,
      publicClient: this.publicClient,
      chainId: this.chain.id,
    });
  }

  /**
   * Prepares data for deleting a premint
   *
   * @param parameters - Parameters for deleting the premint {@link DeletePremintParams}
   * @returns A PremintReturn. {@link PremintReturn}
   */
  async deletePremint(
    params: DeletePremintParams,
  ): Promise<PremintReturn<any>> {
    return deletePremint({
      ...params,
      apiClient: this.apiClient,
      publicClient: this.publicClient,
      chainId: this.chain.id,
    });
  }

  /**
   * Prepares data for creating a premint
   *
   * @param parameters - Parameters for creating the premint {@link CreatePremintParameters}
   * @returns A PremintReturn. {@link PremintReturn}
   */
  async createPremint<T extends PremintConfigVersion = PremintConfigVersion.V2>(
    parameters: CreatePremintParameters<T>,
  ): Promise<PremintReturn<any>> {
    return createPremint({
      ...parameters,
      publicClient: this.publicClient,
      apiClient: this.apiClient,
      chainId: this.chain.id,
    });
  }

  /**
   * Fetches given premint data from the ZORA API.
   *
   * @param address Address for the premint contract
   * @param uid UID for the desired premint
   * @returns PremintSignatureGetResponse of premint data from the API
   */
  async getPremintSignature({
    address,
    uid,
  }: {
    address: Address;
    uid: number;
  }) {
    return await this.apiClient.getSignature({
      collectionAddress: address,
      uid,
    });
  }

  /**
   * Gets the deterministic contract address for a premint collection
   * @param collection Collection to get the address for
   * @returns deterministic contract address
   */
  async getCollectionAddress(collection: ContractCreationConfig) {
    return await getPremintCollectionAddress({
      collection,
      publicClient: this.publicClient,
    });
  }

  /**
   * Check user signature for v1
   *
   * @param data Signature data from the API
   * @returns isValid = signature is valid or not, recoveredSigner = signer from contract
   */
  async isValidSignature<T extends PremintConfigVersion>({
    signature,
    premintConfig,
    premintConfigVersion,
    ...collectionAndOrAddress
  }: {
    signature: Hex;
    premintConfig: PremintConfigForVersion<T>;
    premintConfigVersion?: T;
  } & ContractCreationConfigOrAddress): Promise<{
    isValid: boolean;
    recoveredSigner: Address | undefined;
  }> {
    const collectionAddressToUse = await getPremintCollectionAddress({
      ...collectionAndOrAddress,
      publicClient: this.publicClient,
    });

    const { isAuthorized, recoveredAddress } = await isValidSignature({
      chainId: this.chain.id,
      signature: signature as Hex,
      publicClient: this.publicClient,
      premintConfig,
      premintConfigVersion: premintConfigVersion || PremintConfigVersion.V1,
      collectionAddress: collectionAddressToUse,
      collection: collectionAndOrAddress.collection,
    });

    return { isValid: isAuthorized, recoveredSigner: recoveredAddress };
  }

  protected makeUrls({
    uid,
    address,
    tokenId,
  }: {
    uid?: number;
    tokenId?: bigint;
    address?: Address;
  }): URLSReturnType {
    return makeUrls({
      uid,
      address,
      tokenId,
      chain: this.chain,
    });
  }

  async getMintCosts({
    tokenContract,
    quantityToMint,
    pricePerToken,
  }: {
    quantityToMint: bigint;
    tokenContract: Address;
    pricePerToken: bigint;
  }): Promise<MintCosts> {
    return await getPremintMintCosts({
      publicClient: this.publicClient,
      quantityToMint,
      tokenContract,
      tokenPrice: pricePerToken,
    });
  }

  /**
   * Prepares the parameters to collect a premint; it brings the contract and token onchain, then collects
   * tokens on that contract for the mint recipient.
   *
   * @param parameters - Parameters for collecting the Premint {@link MakeMintParametersArguments}
   * @returns receipt, log, zoraURL
   */
  async makeMintParameters(parameters: MakeMintParametersArguments) {
    return await makeMintParameters({
      ...parameters,
      apiClient: this.apiClient,
      publicClient: this.publicClient,
    });
  }
}

export function createPremintClient(clientConfig: ClientConfig) {
  const { chain, httpClient, publicClient } = setupClient(clientConfig);
  return new PremintClient(chain, publicClient, httpClient);
}

type PremintContext = {
  publicClient: PublicClient;
  apiClient: PremintAPIClient;
  chainId: number;
};

/** ======= ADMIN ======= */

export type SignAndSubmitParams = {
  /** The WalletClient used to sign the premint */
  walletClient: WalletClient;
  /** The account that is to sign the premint */
  account: Account | Address;
  /** If the signature should be checked before submitting it to the api */
  checkSignature?: boolean;
};

export type SignAndSubmitReturn = {
  /** The signature of the Premint  */
  signature: Hex;
  /** The account that signed the Premint */
  signerAccount: Account | Address;
};

export type SubmitParams = {
  /** The signature of the Premint */
  signature: Hex;
  /** If the premint signature should be validated before submitting to the API */
  checkSignature?: boolean;
  /** The account that signed the premint */
  signerAccount: Account | Address;
};

type PremintReturn<T extends PremintConfigVersion> = {
  /** The typedDataDefinition of the Premint which is to be signed the creator. */
  typedDataDefinition: TypedDataDefinition;
  /** The deterministic collection address of the Premint */
  collectionAddress: Address;
  /** Signs the Premint, and submits it and the signature to the Zora Premint API */
  signAndSubmit: (params: SignAndSubmitParams) => Promise<SignAndSubmitReturn>;
  /** For the case where the premint is signed externally, takes the signature for the Premint, and submits it and the Premint to the Zora Premint API */
  submit: (params: SubmitParams) => void;
} & PremintConfigWithVersion<T>;

function makePremintReturn<T extends PremintConfigVersion>({
  premintConfig,
  premintConfigVersion,
  publicClient,
  apiClient,
  chainId,
  ...collectionAndAddress
}: PremintConfigWithVersion<T> &
  ContractCreationConfigAndAddress &
  PremintContext): PremintReturn<T> {
  const { collection, collectionAddress } = collectionAndAddress;
  const typedDataDefinition = premintTypedDataDefinition({
    verifyingContract: collectionAddress,
    premintConfig,
    premintConfigVersion,
    chainId,
  });

  const signAndSubmit = async ({
    walletClient,
    account,
    checkSignature,
  }: SignAndSubmitParams): Promise<SignAndSubmitReturn> => {
    const { signature, signerAccount } = await signPremint({
      account,
      walletClient,
      typedDataDefinition,
    });

    await submit({
      signature,
      checkSignature,
      signerAccount,
    });

    return {
      signature,
      signerAccount,
    };
  };

  const submit = async ({
    signature,
    checkSignature,
    signerAccount,
  }: {
    signature: Hex;
    checkSignature?: boolean;
    signerAccount: Account | Address;
  }) => {
    if (checkSignature) {
      const isAuthorized = await isAuthorizedToCreatePremint({
        collectionAddress,
        additionalAdmins: collection?.additionalAdmins,
        contractAdmin: collection?.contractAdmin,
        publicClient,
        signer: signerAccount,
      });

      if (!isAuthorized) {
        throw new Error("Not authorized to create premint");
      }
    }

    await apiClient.postSignature({
      ...toContractCreationConfigOrAddress(collectionAndAddress),
      signature: signature,
      premintConfig,
      premintConfigVersion,
    });
  };

  return {
    premintConfig,
    premintConfigVersion,
    typedDataDefinition,
    collectionAddress,
    signAndSubmit,
    submit,
  };
}

async function signPremint({
  account,
  walletClient,
  typedDataDefinition,
}: {
  /** The account that is to sign the premint */
  account?: Address | Account;
  /** WalletClient used to sign the premint */
  walletClient: WalletClient;
  /** Data  */
  typedDataDefinition: TypedDataDefinition;
}) {
  if (!account) {
    account = walletClient.account;
  }
  if (!account) {
    throw new Error("No account provided");
  }

  const signature = await walletClient.signTypedData({
    account,
    ...typedDataDefinition,
  });

  return {
    signature,
    signerAccount: account,
  };
}

/** CREATE */

type CreatePremintParameters<T extends PremintConfigVersion> = {
  /** The account to receive the creator reward if it's a free mint, and the paid mint fee if it's a paid mint */
  payoutRecipient: Address;
  /** tokenCreationConfig Token creation settings, optional settings are overridden with sensible defaults */
  tokenCreationConfig: Partial<TokenConfigForVersion<T>> & {
    tokenURI: string;
  };
  /** Premint config version to use, defaults to V2 */
  premintConfigVersion?: T;
  /** uid the UID to use – optional and retrieved as a fresh UID from ZORA by default. */
  uid?: number;
} & ContractCreationConfigOrAddress;

async function createPremint<T extends PremintConfigVersion>({
  payoutRecipient: creatorAccount,
  tokenCreationConfig,
  premintConfigVersion,
  uid,
  publicClient,
  apiClient,
  chainId,
  ...collectionOrAddress
}: CreatePremintParameters<T> & PremintContext) {
  const {
    premintConfig,
    premintConfigVersion: actualVersion,
    collectionAddress: collectionAddressToUse,
  } = await prepareCreatePremintConfig<T>({
    payoutRecipient: creatorAccount,
    ...collectionOrAddress,
    tokenCreationConfig,
    premintConfigVersion,
    uid,
    publicClient,
    apiClient,
    chainId,
  });

  return makePremintReturn({
    premintConfig,
    premintConfigVersion: actualVersion,
    collectionAddress: collectionAddressToUse,
    collection: collectionOrAddress.collection,
    publicClient,
    apiClient,
    chainId,
  });
}

async function prepareCreatePremintConfig<T extends PremintConfigVersion>({
  payoutRecipient,
  tokenCreationConfig,
  premintConfigVersion,
  uid,
  publicClient,
  apiClient,
  chainId,
  ...collectionOrAddress
}: {
  payoutRecipient: Address | Account;
  tokenCreationConfig: Partial<TokenConfigForVersion<T>> & {
    tokenURI: string;
  };
  premintConfigVersion?: T;
  uid?: number;
} & PremintContext &
  ContractCreationConfigOrAddress) {
  const newContractAddress = await getPremintCollectionAddress({
    publicClient,
    ...collectionOrAddress,
  });

  let uidToUse = uid;

  if (typeof uidToUse !== "number") {
    uidToUse = await apiClient.getNextUID(newContractAddress);
  }

  const actualVersion = premintConfigVersion || PremintConfigVersion.V2;

  if (
    !(await supportsPremintVersion({
      version: actualVersion,
      publicClient,
      tokenContract: newContractAddress,
    }))
  ) {
    throw new Error(
      `Premint version ${actualVersion} not supported by contract`,
    );
  }

  const premintConfig = makeNewPremint({
    tokenConfig: makeTokenConfigWithDefaults({
      // @ts-ignore
      premintConfigVersion: actualVersion,
      tokenCreationConfig,
      payoutRecipient:
        typeof payoutRecipient === "string"
          ? payoutRecipient
          : payoutRecipient.address,
      chainId,
    }),
    uid: uidToUse,
  });

  return {
    premintConfig,
    premintConfigVersion: actualVersion,
    collectionAddress: newContractAddress,
  };
}

/** UPDATE */

export type UpdatePremintParams = {
  /** uid of the Premint to update */
  uid: number;
  /** address of the Premint to update */
  collection: Address;
  /** update to apply to the Premint */
  tokenConfigUpdates: Partial<TokenCreationConfig>;
};

async function updatePremint({
  uid,
  collection,
  tokenConfigUpdates,
  apiClient,
  publicClient,
  chainId,
}: UpdatePremintParams & {
  apiClient: PremintAPIClient;
  publicClient: PublicClient;
  chainId: number;
}) {
  const {
    premintConfig,
    collection: collectionCreationConfig,
    premintConfigVersion,
  } = await apiClient.getSignature({
    collectionAddress: collection,
    uid: uid,
  });

  const updatedPremint = applyUpdateToPremint({
    uid: premintConfig.uid,
    version: premintConfig.version,
    tokenConfig: premintConfig.tokenConfig,
    tokenConfigUpdates: tokenConfigUpdates,
  });

  return makePremintReturn({
    premintConfig: updatedPremint,
    premintConfigVersion,
    collectionAddress: collection,
    collection: collectionCreationConfig,
    publicClient,
    apiClient,
    chainId,
  });
}

/** DELETE */

export type DeletePremintParams = {
  /** id of the premint to delete */
  uid: number;
  /** collection address of the Premint to delete */
  collection: Address;
};

async function deletePremint({
  uid,
  collection,
  publicClient,
  apiClient,
  chainId,
}: DeletePremintParams & {
  apiClient: PremintAPIClient;
  publicClient: PublicClient;
  chainId: number;
}) {
  const {
    premintConfig,
    premintConfigVersion,
    collection: collectionCreationConfig,
    collectionAddress,
  } = await apiClient.getSignature({
    collectionAddress: collection,
    uid: uid,
  });

  const deletedPremint = {
    ...premintConfig,
    version: premintConfig.version + 1,
    deleted: true,
  };

  return makePremintReturn({
    premintConfig: deletedPremint,
    premintConfigVersion,
    collectionAddress,
    collection: collectionCreationConfig,
    publicClient,
    apiClient,
    chainId,
  });
}

export type MakeMintParametersArguments = {
  /** uid of the Premint to mint */
  uid: number;
  /** Premint contract address */
  tokenContract: Address;
  /** Account to execute the mint */
  minterAccount: Account | Address;
  /** Minting settings */
  mintArguments?: {
    /** Quantity of tokens to mint */
    quantityToMint: number;
    /** Comment to add to the mint */
    mintComment?: string;
    /** Address to receive the mint referral reward */
    mintReferral?: Address;
    /** Address to receive the minted tokens */
    mintRecipient?: Address;
  };
  /** Account to receive first minter reward, if this mint brings the premint onchain */
  firstMinter?: Address;
};

/** ======== MINTING ======== */

async function makeMintParameters({
  uid,
  tokenContract,
  minterAccount,
  mintArguments,
  firstMinter,
  apiClient,
  publicClient,
}: MakeMintParametersArguments & {
  apiClient: PremintAPIClient;
  publicClient: PublicClient;
}): Promise<
  SimulateContractParameters<
    typeof zoraCreator1155PremintExecutorImplABI,
    "premintV1" | "premintV2",
    any,
    any,
    any,
    Account | Address
  >
> {
  if (mintArguments && mintArguments?.quantityToMint < 1) {
    throw new Error("Quantity to mint cannot be below 1");
  }

  if (!minterAccount) {
    throw new Error("Wallet not passed in");
  }

  const {
    premintConfig,
    premintConfigVersion,
    collection,
    collectionAddress,
    signature,
  } = await apiClient.getSignature({
    collectionAddress: tokenContract,
    uid,
  });

  const numberToMint = BigInt(mintArguments?.quantityToMint || 1);

  if (premintConfigVersion === PremintConfigVersion.V3) {
    throw new Error("PremintV3 not supported in premint SDK");
  }

  const value = (
    await getPremintMintCosts({
      tokenContract,
      quantityToMint: numberToMint,
      publicClient,
      tokenPrice: premintConfig.tokenConfig.pricePerToken,
    })
  ).totalCost;

  const mintArgumentsContract: PremintMintArguments = {
    mintComment: mintArguments?.mintComment || "",
    mintRecipient:
      mintArguments?.mintRecipient ||
      (typeof minterAccount === "string"
        ? minterAccount
        : minterAccount.address),
    mintRewardsRecipients: makeMintRewardsRecipient({
      mintReferral: mintArguments?.mintReferral,
    }),
  };

  const collectionOrEmpty: ContractCreationConfig = collection
    ? defaultAdditionalAdmins(collection)
    : emptyContractCreationConfig();
  const collectionAddressToSubmit = collection
    ? zeroAddress
    : collectionAddress;

  const firstMinterToSubmit: Address =
    firstMinter ||
    (typeof minterAccount === "string" ? minterAccount : minterAccount.address);

  return makeSimulateContractParamaters({
    account: minterAccount,
    abi: zoraCreator1155PremintExecutorImplABI,
    functionName: "premint",
    value,
    address: getPremintExecutorAddress(),
    args: [
      collectionOrEmpty,
      collectionAddressToSubmit,
      encodePremintConfig({
        premintConfig,
        premintConfigVersion,
      }),
      signature,
      numberToMint,
      mintArgumentsContract,
      firstMinterToSubmit,
      zeroAddress,
    ],
  });
}

export function makeUrls({
  uid,
  address,
  tokenId,
  chain,
}: {
  uid?: number;
  tokenId?: bigint;
  address?: Address;
  chain: Chain;
}): URLSReturnType {
  if ((!uid || !tokenId) && !address) {
    return { explorer: null, zoraCollect: null, zoraManage: null };
  }

  const zoraTokenPath = uid ? `premint-${uid}` : tokenId;

  const network = getApiNetworkConfigForChain(chain.id);

  return {
    explorer: tokenId
      ? `https://${chain.blockExplorers?.default.url}/token/${address}/instance/${tokenId}`
      : null,
    zoraCollect: `https://${
      network.isTestnet ? "testnet." : ""
    }zora.co/collect/${
      network.zoraCollectPathChainName
    }:${address}/${zoraTokenPath}`,
    zoraManage: `https://${
      network.isTestnet ? "testnet." : ""
    }zora.co/collect/${
      network.zoraCollectPathChainName
    }:${address}/${zoraTokenPath}`,
  };
}
