import { createPublicClient, decodeEventLog, http, zeroAddress } from "viem";
import type {
  Account,
  Address,
  Chain,
  Hex,
  PublicClient,
  SimulateContractParameters,
  TransactionReceipt,
  WalletClient,
} from "viem";
import { zoraCreator1155PremintExecutorImplABI } from "@zoralabs/protocol-deployments";
import {
  getPremintCollectionAddress,
  premintTypedDataDefinition,
  isValidSignature,
  isAuthorizedToCreatePremint,
  getPremintExecutorAddress,
  applyUpdateToPremint,
  markPremintDeleted,
  makeNewPremint,
  supportsPremintVersion,
  getPremintMintCosts,
  makeMintRewardsRecipient,
  getDefaultFixedPriceMinterAddress,
} from "./preminter";
import {
  PremintConfigVersion,
  ContractCreationConfig,
  TokenConfigForVersion,
  PremintConfigWithVersion,
  TokenCreationConfigV1,
  TokenCreationConfigV2,
  TokenCreationConfig,
  PremintConfigForVersion,
  MintArguments,
} from "./contract-types";
import { PremintAPIClient } from "./premint-api-client";
import type { DecodeEventLogReturnType } from "viem";
import { OPEN_EDITION_MINT_SIZE } from "../constants";
import { IHttpClient } from "src/apis/http-api-base";
import { getApiNetworkConfigForChain } from "src/mint/mint-api-client";
import { MintCosts } from "src/mint/mint-client";
import { makeSimulateContractParamaters } from "src/utils";

type PremintedV2LogType = DecodeEventLogReturnType<
  typeof zoraCreator1155PremintExecutorImplABI,
  "PremintedV2"
>["args"];

type URLSReturnType = {
  explorer: null | string;
  zoraCollect: null | string;
  zoraManage: null | string;
};

type SignedPremintResponse = {
  urls: URLSReturnType;
  uid: number;
  verifyingContract: Address;
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
  creatorAccount,
}: {
  chainId: number;
  premintConfigVersion: PremintConfigVersion;
  tokenCreationConfig: Partial<TokenConfigForVersion<T>> & { tokenURI: string };
  creatorAccount: Address;
}): TokenConfigForVersion<T> => {
  const fixedPriceMinter =
    tokenCreationConfig.fixedPriceMinter ||
    getDefaultFixedPriceMinterAddress(chainId);

  if (premintConfigVersion === PremintConfigVersion.V1) {
    return {
      fixedPriceMinter,
      ...defaultTokenConfigV1MintArguments(),
      royaltyRecipient: creatorAccount,
      ...tokenCreationConfig,
    };
  } else if (premintConfigVersion === PremintConfigVersion.V2) {
    return {
      fixedPriceMinter,
      ...defaultTokenConfigV2MintArguments(),
      payoutRecipient: creatorAccount,
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
 * Currently only supports V1 premints.
 */
class PremintClient {
  readonly apiClient: PremintAPIClient;
  readonly publicClient: PublicClient;
  readonly chain: Chain;

  constructor(
    chain: Chain,
    publicClient?: PublicClient,
    httpClient?: IHttpClient,
  ) {
    this.chain = chain;
    this.apiClient = new PremintAPIClient(chain.id, httpClient);
    this.publicClient =
      publicClient || createPublicClient({ chain, transport: http() });
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
   * Update existing premint given collection address and UID of existing premint.
   *
   * 1. Loads existing premint token
   * 2. Updates with settings passed into function
   * 3. Increments the version field
   * 4. Re-signs the premint
   * 5. Uploads the premint to the ZORA API
   *
   * Updates existing premint
   * @param settings Settings for the new premint
   * @param settings.account Account to sign the premint update from. Taken from walletClient if none passed in.
   * @param settings.collection Collection information for the mint
   * @param settings.walletClient viem wallet client to use to sign
   * @param settings.uid UID
   * @param settings.token Mint argument settings, optional settings are overridden with sensible defaults.
   *
   */
  async updatePremint({
    walletClient,
    uid,
    collection,
    account,
    tokenConfigUpdates,
  }: {
    walletClient: WalletClient;
    uid: number;
    account?: Account | Address;
    collection: Address;
    tokenConfigUpdates: Partial<TokenCreationConfig>;
  }): Promise<SignedPremintResponse> {
    const {
      premintConfig,
      collection: collectionCreationConfig,
      premintConfigVersion,
    } = await this.apiClient.getSignature({
      collectionAddress: collection,
      uid: uid,
    });

    const updatedPremint = applyUpdateToPremint({
      uid: premintConfig.uid,
      version: premintConfig.version,
      tokenConfig: premintConfig.tokenConfig,
      tokenConfigUpdates: tokenConfigUpdates,
    });

    return await this.signAndSubmitPremint({
      walletClient,
      account,
      checkSignature: true,
      verifyingContract: collection,
      collection: collectionCreationConfig,
      premintConfig: updatedPremint,
      premintConfigVersion: premintConfigVersion,
    });
  }

  /**
   * Delete premint.
   *
   * 1. Loads current premint from collection address with UID
   * 2. Increments version and marks as deleted
   * 3. Signs new premint version
   * 4. Sends to ZORA Premint API
   *
   * Deletes existing premint
   * @param settings.collection collection address
   * @param settings.uid UID
   * @param settings.walletClient viem wallet client to use to sign
   *
   */
  async deletePremint({
    walletClient,
    uid,
    account,
    collection,
  }: {
    walletClient: WalletClient;
    uid: number;
    account?: Account | Address;
    collection: Address;
  }) {
    const {
      premintConfig,
      premintConfigVersion,
      collection: collectionCreationConfig,
    } = await this.apiClient.getSignature({
      collectionAddress: collection,
      uid: uid,
    });

    const deletedPremint = markPremintDeleted(premintConfig);

    return await this.signAndSubmitPremint({
      walletClient,
      account,
      checkSignature: false,
      verifyingContract: collection,
      collection: collectionCreationConfig,
      premintConfig: deletedPremint,
      premintConfigVersion,
    });
  }

  /**
   * Internal function to sign and submit a premint request.
   *
   * @param premintArguments Arguments to premint
   * @returns
   */
  private async signAndSubmitPremint<T extends PremintConfigVersion>(
    params: SignAndSubmitPremintParams<T>,
  ): Promise<SignedPremintResponse> {
    const { verifyingContract } = await signAndSubmitPremint({
      ...params,
      chainId: this.chain.id,
      apiClient: this.apiClient,
      publicClient: this.publicClient,
    });

    const uid = params.premintConfig.uid;

    return {
      urls: this.makeUrls({ address: verifyingContract, uid }),
      uid,
      verifyingContract,
    };
  }

  /**
   * Create premint
   *
   * @param settings Settings for the new premint
   * @param settings.account Account to sign the premint with. Taken from walletClient if none passed in.
   * @param settings.collection Collection information for the mint
   * @param settings.tokenCreationConfig Mint argument settings, optional settings are overridden with sensible defaults.
   * @param setings.premintConfigVersion Premint config version to use, defaults to V2
   * @param settings.uid the UID to use – optional and retrieved as a fresh UID from ZORA by default.
   * @param settings.checkSignature if the signature should have a pre-flight check. Not required but helpful for debugging.
   * @returns premint url, uid, newContractAddress, and premint object
   */
  async createPremint<
    T extends PremintConfigVersion = PremintConfigVersion.V2,
  >({
    creatorAccount,
    collection,
    tokenCreationConfig,
    premintConfigVersion,
    walletClient,
    uid,
    checkSignature = false,
  }: {
    creatorAccount: Address | Account;
    checkSignature?: boolean;
    walletClient: WalletClient;
    collection: ContractCreationConfig;
    tokenCreationConfig: Partial<TokenConfigForVersion<T>> & {
      tokenURI: string;
    };
    premintConfigVersion?: T;
    uid?: number;
  }) {
    const newContractAddress = await getPremintCollectionAddress({
      publicClient: this.publicClient,
      collection,
    });

    let uidToUse = uid;

    if (typeof uidToUse !== "number") {
      uidToUse = await this.apiClient.getNextUID(newContractAddress);
    }

    const actualVersion = premintConfigVersion || PremintConfigVersion.V1;

    if (
      !(await supportsPremintVersion({
        version: actualVersion,
        publicClient: this.publicClient,
        tokenContract: newContractAddress,
      }))
    ) {
      throw new Error(
        `Premint version ${actualVersion} not supported by contract`,
      );
    }

    const premintConfig = makeNewPremint({
      tokenConfig: makeTokenConfigWithDefaults({
        premintConfigVersion: actualVersion,
        tokenCreationConfig,
        creatorAccount:
          typeof creatorAccount === "string"
            ? creatorAccount
            : creatorAccount.address,
        chainId: this.chain.id,
      }),
      uid: uidToUse,
    });

    return await this.signAndSubmitPremint({
      verifyingContract: newContractAddress,
      premintConfig,
      premintConfigVersion: actualVersion,
      checkSignature,
      account: creatorAccount,
      walletClient,
      collection,
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
    collection,
    premintConfig,
    premintConfigVersion,
  }: {
    signature: Hex;
    collection: ContractCreationConfig;
    premintConfig: PremintConfigForVersion<T>;
    premintConfigVersion?: T;
  }): Promise<{
    isValid: boolean;
    recoveredSigner: Address | undefined;
  }> {
    const { isAuthorized, recoveredAddress } = await isValidSignature({
      chainId: this.chain.id,
      signature: signature as Hex,
      collection: collection,
      publicClient: this.publicClient,
      premintConfig,
      premintConfigVersion: premintConfigVersion || PremintConfigVersion.V1,
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
   * Execute premint on-chain
   *
   * @param settings.data Data from the API for the mint
   * @param settings.account Optional account (if omitted taken from wallet client) for the account executing the premint.
   * @param settings.walletClient WalletClient to send execution from.
   * @param settings.mintArguments User minting arguments.
   * @param settings.mintArguments.quantityToMint Quantity to mint, optional, defaults to 1.
   * @param settings.mintArguments.mintComment Optional mint comment, optional, omits when not included.
   * @param settings.publicClient Optional public client for preflight checks.
   * @returns receipt, log, zoraURL
   */
  async makeMintParameters({
    uid,
    tokenContract,
    minterAccount,
    mintArguments,
  }: {
    uid: number;
    tokenContract: Address;
    minterAccount: Account | Address;
    mintArguments?: {
      quantityToMint: number;
      mintComment?: string;
      mintReferral?: Address;
      platformReferral?: Address;
      mintRecipient?: Address;
    };
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

    const { premintConfig, premintConfigVersion, collection, signature } =
      await this.getPremintSignature({
        address: tokenContract,
        uid,
      });

    const numberToMint = BigInt(mintArguments?.quantityToMint || 1);

    const value = (
      await getPremintMintCosts({
        tokenContract,
        quantityToMint: numberToMint,
        publicClient: this.publicClient,
        tokenPrice: premintConfig.tokenConfig.pricePerToken,
      })
    ).totalCost;

    const mintArgumentsContract: MintArguments = {
      mintComment: mintArguments?.mintComment || "",
      mintRecipient:
        mintArguments?.mintRecipient ||
        (typeof minterAccount === "string"
          ? minterAccount
          : minterAccount.address),
      mintRewardsRecipients: makeMintRewardsRecipient({
        mintReferral: mintArguments?.mintReferral,
        platformReferral: mintArguments?.platformReferral,
      }),
    };

    if (premintConfigVersion === PremintConfigVersion.V1) {
      return makeSimulateContractParamaters({
        account: minterAccount,
        abi: zoraCreator1155PremintExecutorImplABI,
        functionName: "premintV1",
        value,
        address: getPremintExecutorAddress(),
        args: [
          collection,
          premintConfig,
          signature,
          numberToMint,
          mintArgumentsContract,
        ],
      });
    } else if (premintConfigVersion === PremintConfigVersion.V2) {
      return makeSimulateContractParamaters({
        account: minterAccount,
        abi: zoraCreator1155PremintExecutorImplABI,
        functionName: "premintV2",
        value,
        address: getPremintExecutorAddress(),
        args: [
          collection,
          premintConfig,
          signature,
          numberToMint,
          mintArgumentsContract,
        ],
      });
    }

    throw new Error(`Invalid premint config version ${premintConfigVersion}`);
  }
}

export function createPremintClient({
  chain,
  httpClient,
  publicClient,
}: {
  chain: Chain;
  publicClient?: PublicClient;
  httpClient?: IHttpClient;
}) {
  return new PremintClient(chain, publicClient, httpClient);
}

function makeUrls({
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

type SignAndSubmitPremintParams<T extends PremintConfigVersion> = {
  walletClient: WalletClient;
  verifyingContract: Address;
  checkSignature: boolean;
  account?: Address | Account;
  collection: ContractCreationConfig;
} & PremintConfigWithVersion<T>;

async function signAndSubmitPremint<T extends PremintConfigVersion>({
  walletClient,
  verifyingContract,
  account,
  checkSignature,
  collection,
  chainId,
  publicClient,
  apiClient,
  ...premintConfigAndVersion
}: SignAndSubmitPremintParams<T> & {
  chainId: number;
  publicClient: PublicClient;
  apiClient: PremintAPIClient;
}) {
  if (!account) {
    account = walletClient.account;
  }
  if (!account) {
    throw new Error("No account provided");
  }

  const signature = await walletClient.signTypedData({
    account,
    ...premintTypedDataDefinition({
      verifyingContract,
      ...premintConfigAndVersion,
      chainId,
    }),
  });

  if (checkSignature) {
    const isAuthorized = await isAuthorizedToCreatePremint({
      collection,
      publicClient,
      signer: typeof account === "string" ? account : account.address,
      collectionAddress: await getPremintCollectionAddress({
        collection,
        publicClient,
      }),
    });
    if (!isAuthorized) {
      throw new Error("Not authorized to create premint");
    }
  }

  const premint = await apiClient.postSignature({
    collection: collection,
    signature: signature,
    ...premintConfigAndVersion,
  });

  return { premint, verifyingContract };
}
