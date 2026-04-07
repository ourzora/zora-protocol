import { decodeEventLog, zeroAddress } from "viem";
import type {
  Account,
  Address,
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
  isAuthorizedToCreatePremint,
  getPremintExecutorAddress,
  getPremintMintCosts,
  makeMintRewardsRecipient,
  emptyContractCreationConfig,
  defaultAdditionalAdmins,
  toContractCreationConfigOrAddress,
  getPremintMintFee,
} from "./preminter";
import {
  PremintConfigVersion,
  ContractCreationConfig,
  PremintConfigWithVersion,
  PremintMintArguments,
  premintTypedDataDefinition,
} from "@zoralabs/protocol-deployments";
import { IPremintAPI, IPremintGetter } from "./premint-api-client";
import type { DecodeEventLogReturnType } from "viem";
import {
  makeContractParameters,
  mintRecipientOrAccount,
  PublicClient,
} from "src/utils";
import { ContractCreationConfigAndAddress } from "./contract-types";
import {
  MakeMintParametersArgumentsBase,
  MakePremintMintParametersArguments,
  MintCosts,
} from "src/mint/types";
import { PremintFromApi } from "./conversions";
import { SimulateContractParametersWithAccount } from "src/types";
import { getApiNetworkConfigForChain } from "src/apis/network-config";

type PremintedV2LogType = DecodeEventLogReturnType<
  typeof zoraCreator1155PremintExecutorImplABI,
  "PremintedV2"
>["args"];

type URLSReturnType = {
  explorer: null | string;
  zoraCollect: null | string;
  zoraManage: null | string;
};

/**
 * Gets the preminted log from receipt
 *
 * @param receipt Preminted log from receipt
 * @returns Premint event arguments
 */
function getPremintedLogFromReceipt(
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
export class PremintClient {
  readonly apiClient: IPremintAPI;
  readonly publicClient: PublicClient;
  readonly chainId: number;

  constructor({
    chainId,
    publicClient,
    premintApi,
  }: {
    chainId: number;
    publicClient: PublicClient;
    premintApi: IPremintAPI;
  }) {
    this.chainId = chainId;
    this.apiClient = premintApi;
    this.publicClient = publicClient;
  }

  getDataFromPremintReceipt(
    receipt: TransactionReceipt,
    blockExplorerUrl?: string,
  ) {
    return getDataFromPremintReceipt(receipt, this.chainId, blockExplorerUrl);
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
      chainId: this.chainId,
    });
  }

  /**
   * Fetches given premint data from the ZORA API.
   *
   * @param address Address for the premint contract
   * @param uid UID for the desired premint
   * @returns PremintSignatureGetResponse of premint data from the API
   */
  async getPremint({ address, uid }: { address: Address; uid: number }) {
    return await this.apiClient.get({
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
      contract: collection,
      publicClient: this.publicClient,
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
  async makeMintParameters({
    minterAccount,
    tokenContract,
    uid,
    mintArguments,
    firstMinter,
  }: MakeMintParametersArguments) {
    return await collectPremint({
      uid,
      tokenContract,
      minterAccount,
      quantityToMint: mintArguments?.quantityToMint || 1n,
      mintComment: mintArguments?.mintComment,
      mintReferral: mintArguments?.mintReferral,
      mintRecipient: mintArguments?.mintRecipient,
      firstMinter,
      premintGetter: this.apiClient,
      publicClient: this.publicClient,
    });
  }
}

export function getDataFromPremintReceipt(
  receipt: TransactionReceipt,
  chainId: number,
  blockExplorerUrl?: string,
) {
  const premintedLog = getPremintedLogFromReceipt(receipt);
  return {
    tokenId: premintedLog?.tokenId,
    collectionAddres: premintedLog?.contractAddress,
    premintedLog,
    urls: makeUrls({
      address: premintedLog?.contractAddress,
      tokenId: premintedLog?.tokenId,
      chainId,
      blockExplorerUrl,
    }),
  };
}

type PremintContext = {
  publicClient: PublicClient;
  apiClient: IPremintAPI;
  chainId: number;
};

/** ======= ADMIN ======= */

type SignAndSubmitParams = {
  /** The WalletClient used to sign the premint */
  walletClient: WalletClient;
} & CheckSignatureParams;

type SignAndSubmitReturn = {
  /** The signature of the Premint  */
  signature: Hex;
  /** The account that signed the Premint */
  signerAccount: Account | Address;
};

type CheckSignatureParams =
  | {
      /** If the premint signature should be validated before submitting to the API */
      checkSignature: true;
      /** Account that signed the premint */
      account: Account | Address;
    }
  | {
      /** If the premint signature should be validated before submitting to the API */
      checkSignature?: false;
      account?: Account | Address;
    };

type SubmitParams = {
  /** The signature of the Premint */
  signature: Hex;
} & CheckSignatureParams;

type PremintReturn<T extends PremintConfigVersion> = {
  /** The typedDataDefinition of the Premint which is to be signed the creator. */
  typedDataDefinition: TypedDataDefinition;
  /** The deterministic collection address of the Premint */
  collectionAddress: Address;
  /** Signs the Premint, and submits it and the signature to the Zora Premint API */
  signAndSubmit: (params: SignAndSubmitParams) => Promise<SignAndSubmitReturn>;
  /** For the case where the premint is signed externally, takes the signature for the Premint, and submits it and the Premint to the Zora Premint API */
  submit: (params: SubmitParams) => Promise<void>;
  urls: URLSReturnType;
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
    account: account,
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
      account: signerAccount,
    });

    return {
      signature,
      signerAccount,
    };
  };

  const submit = async ({
    signature,
    checkSignature,
    account,
  }: SubmitParams) => {
    if (checkSignature) {
      const isAuthorized = await isAuthorizedToCreatePremint({
        collectionAddress,
        additionalAdmins: collection?.additionalAdmins,
        contractAdmin: collection?.contractAdmin,
        publicClient,
        signer: account,
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

  const urls = makeUrls({
    chainId,
    address: collectionAddress,
    uid: premintConfig.uid,
  });

  return {
    premintConfig,
    premintConfigVersion,
    typedDataDefinition,
    collectionAddress,
    signAndSubmit,
    submit,
    urls,
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

/** DELETE */

type DeletePremintParams = {
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
  apiClient: IPremintAPI;
  publicClient: PublicClient;
  chainId: number;
}) {
  const {
    premint: { premintConfig, premintConfigVersion },
    collection: collectionCreationConfig,
    collectionAddress,
  } = await apiClient.get({
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

type MakeMintParametersArguments = {
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

async function collectPremint({
  uid,
  tokenContract,
  minterAccount,
  quantityToMint,
  mintComment = "",
  mintReferral,
  mintRecipient,
  firstMinter,
  premintGetter,
  publicClient,
}: Omit<MakePremintMintParametersArguments, "mintType"> & {
  premintGetter: IPremintGetter;
  publicClient: PublicClient;
}): Promise<
  SimulateContractParameters<
    typeof zoraCreator1155PremintExecutorImplABI,
    "premint",
    any,
    any,
    any,
    Account | Address
  >
> {
  if (typeof quantityToMint !== "undefined" && quantityToMint < 1) {
    throw new Error("Quantity to mint cannot be below 1");
  }

  const premint = await premintGetter.get({
    collectionAddress: tokenContract,
    uid,
  });

  const mintFee = await getPremintMintFee({
    tokenContract,
    publicClient,
  });

  return buildPremintMintCall({
    mintArguments: {
      minterAccount,
      quantityToMint,
      firstMinter,
      mintComment,
      mintRecipient,
      mintReferral,
    },
    mintFee,
    premint,
  });
}

export const buildPremintMintCall = ({
  mintArguments: {
    minterAccount,
    mintComment = "",
    mintRecipient,
    mintReferral,
    firstMinter,
    quantityToMint,
  },
  premint: { collection, collectionAddress, premint, signature },
  mintFee,
}: {
  mintArguments: Omit<MakeMintParametersArgumentsBase, "tokenContract"> & {
    firstMinter?: Address;
  };
  premint: Pick<
    PremintFromApi,
    "collection" | "collectionAddress" | "premint" | "signature"
  >;
  mintFee: bigint;
}): SimulateContractParametersWithAccount => {
  const mintArgumentsContract: PremintMintArguments = {
    mintComment: mintComment,
    mintRecipient: mintRecipientOrAccount({
      mintRecipient,
      minterAccount,
    }),
    mintRewardsRecipients: makeMintRewardsRecipient({
      mintReferral,
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

  if (premint.premintConfigVersion === PremintConfigVersion.V3) {
    throw new Error("PremintV3 not supported in premint SDK");
  }

  const value =
    (mintFee + premint.premintConfig.tokenConfig.pricePerToken) *
    BigInt(quantityToMint);

  return makeContractParameters({
    account: minterAccount,
    abi: zoraCreator1155PremintExecutorImplABI,
    functionName: "premint",
    value,
    address: getPremintExecutorAddress(),
    args: [
      collectionOrEmpty,
      collectionAddressToSubmit,
      encodePremintConfig(premint),
      signature,
      BigInt(quantityToMint),
      mintArgumentsContract,
      firstMinterToSubmit,
      zeroAddress,
    ],
  });
};

function makeUrls({
  uid,
  address,
  tokenId,
  chainId,
  blockExplorerUrl,
}: {
  uid?: number;
  tokenId?: bigint;
  address?: Address;
  chainId: number;
  blockExplorerUrl?: string;
}): URLSReturnType {
  if ((!uid || !tokenId) && !address) {
    return { explorer: null, zoraCollect: null, zoraManage: null };
  }

  const zoraTokenPath = uid ? `premint-${uid}` : tokenId;

  const network = getApiNetworkConfigForChain(chainId);

  return {
    explorer: tokenId
      ? `https://${blockExplorerUrl}/token/${address}/instance/${tokenId}`
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
