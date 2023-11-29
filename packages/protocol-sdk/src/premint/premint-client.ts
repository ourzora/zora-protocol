import { createPublicClient, decodeEventLog, http } from "viem";
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
import {
  zoraCreator1155PremintExecutorImplABI,
  zoraCreator1155PremintExecutorImplAddress,
  zoraCreatorFixedPriceSaleStrategyAddress,
} from "@zoralabs/protocol-deployments";
import {
  PremintConfigAndVersion,
  PremintConfigV1,
  PremintConfigV2,
  PremintConfigVersion,
  getPremintCollectionAddress,
  premintTypedDataDefinition,
  ContractCreationConfig,
  isValidSignature,
  isAuthorizedToCreatePremint,
  getPremintExecutorAddress,
} from "./preminter";
import type {
  PremintSignatureGetResponse,
  PremintSignatureResponse,
} from "./premint-api-client";
import { PremintAPIClient } from "./premint-api-client";
import type { DecodeEventLogReturnType } from "viem";
import { OPEN_EDITION_MINT_SIZE } from "../constants";
import { REWARD_PER_TOKEN } from "src/apis/chain-constants";
import { IHttpClient } from "src/apis/http-api-base";
import { getApiNetworkConfigForChain } from "src/mint/mint-api-client";

type MintArgumentsSettings = {
  tokenURI: string;
  maxSupply?: bigint;
  maxTokensPerAddress?: bigint;
  pricePerToken?: bigint;
  mintStart?: bigint;
  mintDuration?: bigint;
  royaltyMintSchedule?: number;
  royaltyBPS?: number;
  royaltyRecipient?: Address;
  fixedPriceMinter?: Address;
};

type PremintedLogType = DecodeEventLogReturnType<
  typeof zoraCreator1155PremintExecutorImplABI,
  "Preminted"
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
  premint: PremintSignatureResponse;
};

export const DefaultMintArguments = {
  maxSupply: OPEN_EDITION_MINT_SIZE,
  maxTokensPerAddress: 0n,
  pricePerToken: 0n,
  mintDuration: BigInt(60 * 60 * 24 * 7), // 1 week
  mintStart: 0n,
  royaltyMintSchedule: 0,
  royaltyBPS: 1000, // 10%,
};

/**
 * Gets the preminted log from receipt
 *
 * @param receipt Preminted log from receipt
 * @returns Premint event arguments
 */
export function getPremintedLogFromReceipt(
  receipt: TransactionReceipt,
): PremintedLogType | undefined {
  for (const data of receipt.logs) {
    try {
      const decodedLog = decodeEventLog({
        abi: zoraCreator1155PremintExecutorImplABI,
        eventName: "Preminted",
        ...data,
      });
      if (decodedLog.eventName === "Preminted") {
        return decodedLog.args;
      }
    } catch (err: any) {}
  }
}

/**
 * Convert server to on-chain types for a premint
 *
 * @param premint Premint object from the server to convert to one that's compatible with viem
 * @returns Viem type-compatible premint object
 */
export const convertPremintV1 = (
  premint: PremintSignatureGetResponse["premint"],
) => ({
  ...premint,
  tokenConfig: {
    ...premint.tokenConfig,
    fixedPriceMinter: premint.tokenConfig.fixedPriceMinter as Address,
    royaltyRecipient: premint.tokenConfig.royaltyRecipient as Address,
    maxSupply: BigInt(premint.tokenConfig.maxSupply),
    pricePerToken: BigInt(premint.tokenConfig.pricePerToken),
    mintStart: BigInt(premint.tokenConfig.mintStart),
    mintDuration: BigInt(premint.tokenConfig.mintDuration),
    maxTokensPerAddress: BigInt(premint.tokenConfig.maxTokensPerAddress),
  },
});

export const convertCollection = (
  collection: PremintSignatureGetResponse["collection"],
) => ({
  ...collection,
  contractAdmin: collection.contractAdmin as Address,
});

/**
 * Convert on-chain types for a premint to a server safe type
 *
 * @param premint Premint object from viem to convert to a JSON compatible type.
 * @returns JSON compatible premint
 */
export const encodePremintV1ForAPI = ({
  tokenConfig,
  ...premint
}: PremintConfigV1) => ({
  ...premint,
  tokenConfig: {
    ...tokenConfig,
    maxSupply: tokenConfig.maxSupply.toString(),
    pricePerToken: tokenConfig.pricePerToken.toString(),
    mintStart: tokenConfig.mintStart.toString(),
    mintDuration: tokenConfig.mintDuration.toString(),
    maxTokensPerAddress: tokenConfig.maxTokensPerAddress.toString(),
  },
});

export const encodePremintV2ForAPI = ({
  tokenConfig,
  ...premint
}: PremintConfigV2) => ({
  ...premint,
  tokenConfig: {
    ...tokenConfig,
    maxSupply: tokenConfig.maxSupply.toString(),
    pricePerToken: tokenConfig.pricePerToken.toString(),
    mintStart: tokenConfig.mintStart.toString(),
    mintDuration: tokenConfig.mintDuration.toString(),
    maxTokensPerAddress: tokenConfig.maxTokensPerAddress.toString(),
  },
});

export const encodePremintForAPI = ({
  premintConfig,
  premintConfigVersion,
}: PremintConfigAndVersion) => {
  if (premintConfigVersion === PremintConfigVersion.V1) {
    return encodePremintV1ForAPI(premintConfig);
  }
  if (premintConfigVersion === PremintConfigVersion.V2) {
    return encodePremintV2ForAPI(premintConfig);
  }
  throw new Error(`Invalid premint config version ${premintConfigVersion}`);
};

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

  /**
   * The fixed price minter address is the same across all chains for our current
   * deployer strategy.
   * Can be overridden as needed by making a parent class.
   *
   * @returns Fixed price sale strategy
   */
  getFixedPriceMinterAddress() {
    return zoraCreatorFixedPriceSaleStrategyAddress[999];
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
    token,
    account,
  }: {
    walletClient: WalletClient;
    uid: number;
    token: MintArgumentsSettings;
    account?: Account | Address;
    collection: Address;
  }): Promise<SignedPremintResponse> {
    const signatureResponse = await this.apiClient.getSignature({
      collection_address: collection.toLowerCase(),
      uid: uid,
    });

    const convertedPremint = convertPremintV1(signatureResponse.premint);
    const signerData = {
      ...signatureResponse,
      premint: {
        ...convertedPremint,
        tokenConfig: {
          ...convertedPremint.tokenConfig,
          ...token,
        },
      },
    };

    return await this.signAndSubmitPremint({
      walletClient,
      account,
      checkSignature: false,
      verifyingContract: collection,
      uid: uid,
      collection: {
        ...signerData.collection,
        contractAdmin: signerData.collection.contractAdmin as Address,
      },
      premintConfig: signerData.premint,
      premintConfigVersion: PremintConfigVersion.V1,
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
    const signatureResponse = await this.apiClient.getSignature({
      collection_address: collection.toLowerCase(),
      uid: uid,
    });

    const signerData = {
      ...signatureResponse,
      collection: convertCollection(signatureResponse.collection),
      premint: {
        ...convertPremintV1(signatureResponse.premint),
        deleted: true,
      },
    };

    return await this.signAndSubmitPremint({
      walletClient,
      account,
      checkSignature: false,
      verifyingContract: collection,
      uid: uid,
      collection: signerData.collection,
      premintConfig: signerData.premint,
      premintConfigVersion: PremintConfigVersion.V1,
    });
  }

  /**
   * Internal function to sign and submit a premint request.
   *
   * @param premintArguments Arguments to premint
   * @returns
   */
  private async signAndSubmitPremint({
    walletClient,
    verifyingContract,
    uid,
    account,
    checkSignature,
    collection,
    ...premintConfigAndVersion
  }: {
    uid: number;
    walletClient: WalletClient;
    verifyingContract: Address;
    checkSignature: boolean;
    account?: Address | Account;
    collection: PremintSignatureGetResponse["collection"];
  } & PremintConfigAndVersion) {
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
        chainId: this.chain.id,
      }),
    });

    if (checkSignature) {
      const convertedCollection = convertCollection(collection);
      const isAuthorized = await isAuthorizedToCreatePremint({
        collection: convertCollection(collection),
        signature,
        publicClient: this.publicClient,
        signer: typeof account === "string" ? account : account.address,
        collectionAddress: await this.getCollectionAddress(convertedCollection),
        ...premintConfigAndVersion,
      });
      if (!isAuthorized) {
        throw new Error("Not authorized to create premint");
      }
    }

    if (
      premintConfigAndVersion.premintConfigVersion === PremintConfigVersion.V2
    ) {
      throw new Error("premint config v2 not supported yet");
    }

    const apiData = {
      collection,
      premint: encodePremintV1ForAPI(premintConfigAndVersion.premintConfig),
      signature: signature,
    };

    const premint = await this.apiClient.postSignature(apiData);

    return {
      urls: this.makeUrls({ address: verifyingContract, uid }),
      uid,
      verifyingContract,
      premint,
    };
  }

  /**
   * Create premint
   *
   * @param settings Settings for the new premint
   * @param settings.account Account to sign the premint with. Taken from walletClient if none passed in.
   * @param settings.collection Collection information for the mint
   * @param settings.token Mint argument settings, optional settings are overridden with sensible defaults.
   * @param settings.publicClient Public client (optional) – instantiated if not passed in with defaults.
   * @param settings.walletClient Required wallet client for signing the premint message.
   * @param settings.executionSettings Execution settings for premint options
   * @param settings.executionSettings.deleted If this UID should be deleted. If omitted, set to false.
   * @param settings.executionSettings.uid the UID to use – optional and retrieved as a fresh UID from ZORA by default.
   * @param settings.checkSignature if the signature should have a pre-flight check. Not required but helpful for debugging.
   * @returns premint url, uid, newContractAddress, and premint object
   */
  async createPremint({
    account,
    collection,
    token,
    walletClient,
    executionSettings,
    checkSignature = false,
  }: {
    account: Address;
    checkSignature?: boolean;
    walletClient: WalletClient;
    collection: PremintSignatureGetResponse["collection"];
    token: MintArgumentsSettings;
    executionSettings?: {
      deleted?: boolean;
      uid?: number;
    };
  }) {
    const newContractAddress = await getPremintCollectionAddress({
      publicClient: this.publicClient,
      collection: convertCollection(collection),
    });

    const tokenConfig = {
      ...DefaultMintArguments,
      fixedPriceMinter: this.getFixedPriceMinterAddress(),
      royaltyRecipient: account,
      ...token,
    };

    let uid = executionSettings?.uid;
    if (!uid) {
      const uidResponse = await this.apiClient.getNextUID({
        collection_address: newContractAddress.toLowerCase(),
      });
      uid = uidResponse.next_uid;
    }

    if (!uid) {
      throw new Error("UID is missing but required");
    }

    let deleted = executionSettings?.deleted || false;

    const premintConfig: PremintConfigV1 = {
      tokenConfig: tokenConfig,
      uid,
      version: 1,
      deleted,
    };

    return await this.signAndSubmitPremint({
      uid,
      verifyingContract: newContractAddress,
      premintConfig,
      premintConfigVersion: PremintConfigVersion.V1,
      checkSignature,
      account,
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
  async getPremintData({
    address,
    uid,
  }: {
    address: string;
    uid: number;
  }): Promise<PremintSignatureGetResponse> {
    return await this.apiClient.getSignature({
      collection_address: address,
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
  async isValidSignature(data: PremintSignatureResponse): Promise<{
    isValid: boolean;
    recoveredSigner: Address | undefined;
  }> {
    const {isAuthorized, recoveredAddress }= await isValidSignature({
      chainId: this.chain.id,
      signature: data.signature as Hex,
      premintConfig: convertPremintV1(data.premint),
      premintConfigVersion: PremintConfigVersion.V1,
      collection: convertCollection(data.collection),
      publicClient: this.publicClient,
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
    if ((!uid || !tokenId) && !address) {
      return { explorer: null, zoraCollect: null, zoraManage: null };
    }

    const zoraTokenPath = uid ? `premint-${uid}` : tokenId;

    const network = getApiNetworkConfigForChain(this.chain.id);

    return {
      explorer: tokenId
        ? `https://${this.chain.blockExplorers?.default.url}/token/${address}/instance/${tokenId}`
        : null,
      zoraCollect: `https://${
        network.isTestnet ? "testnet." : ""
      }zora.co/collect/${
        network.zoraPathChainName
      }:${address}/${zoraTokenPath}`,
      zoraManage: `https://${
        network.isTestnet ? "testnet." : ""
      }zora.co/collect/${
        network.zoraPathChainName
      }:${address}/${zoraTokenPath}`,
    };
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
    data,
    account,
    mintArguments,
  }: {
    data: PremintSignatureGetResponse;
    account: Account | Address;
    mintArguments?: {
      quantityToMint: number;
      mintComment?: string;
    };
  }): Promise<SimulateContractParameters<typeof zoraCreator1155PremintExecutorImplABI, "premint">> {
    if (mintArguments && mintArguments?.quantityToMint < 1) {
      throw new Error("Quantity to mint cannot be below 1");
    }

    const numberToMint = BigInt(mintArguments?.quantityToMint || 1);
    const args = [
      convertCollection(data.collection),
      convertPremintV1(data.premint),
      data.signature as Hex,
      numberToMint,
      mintArguments?.mintComment || "",
    ] as const;

    if (!account) {
      throw new Error("Wallet not passed in");
    }

    const value = numberToMint * REWARD_PER_TOKEN;

    const request = {
      account,
      abi: zoraCreator1155PremintExecutorImplABI,
      functionName: "premint",
      value,
      address: getPremintExecutorAddress(),
      args,
    } satisfies SimulateContractParameters<typeof zoraCreator1155PremintExecutorImplABI, "premint">;

    return request;
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
