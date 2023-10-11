import { createPublicClient, decodeEventLog, http, parseEther } from "viem";
import type {
  Account,
  Address,
  Chain,
  Hex,
  PublicClient,
  TransactionReceipt,
  WalletClient,
} from "viem";
import {
  zoraCreator1155PremintExecutorImplABI,
  zoraCreator1155PremintExecutorImplAddress,
  zoraCreatorFixedPriceSaleStrategyAddress,
} from "@zoralabs/protocol-deployments";
import { foundry, zora, zoraTestnet } from "viem/chains";
import { PremintConfigV1 as PremintConfig, preminterTypedDataDefinitionV1 as preminterTypedDataDefinition } from "./preminter";
import type {
  BackendChainNames as BackendChainNamesType,
  PremintSignatureGetResponse,
  PremintSignatureResponse,
} from "./premint-api-client";
import { PremintAPIClient } from "./premint-api-client";
import type { DecodeEventLogReturnType } from "viem";

export const BackendChainNamesLookup = {
  ZORA_MAINNET: "ZORA-MAINNET",
  ZORA_GOERLI: "ZORA-GOERLI",
} as const;

export type NetworkConfig = {
  chainId: number;
  zoraPathChainName: string;
  zoraBackendChainName: BackendChainNamesType;
  isTestnet: boolean;
};

export const REWARD_PER_TOKEN = parseEther("0.000777");

export const networkConfigByChain: Record<number, NetworkConfig> = {
  [zora.id]: {
    chainId: zora.id,
    isTestnet: false,
    zoraPathChainName: "zora",
    zoraBackendChainName: BackendChainNamesLookup.ZORA_MAINNET,
  },
  [zoraTestnet.id]: {
    chainId: zora.id,
    isTestnet: true,
    zoraPathChainName: "zgor",
    zoraBackendChainName: BackendChainNamesLookup.ZORA_GOERLI,
  },
  [foundry.id]: {
    chainId: foundry.id,
    isTestnet: true,
    zoraPathChainName: "zgor",
    zoraBackendChainName: BackendChainNamesLookup.ZORA_GOERLI,
  },
};

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

type ExecutedPremintResponse = {
  receipt: TransactionReceipt;
  premintedLog?: PremintedLogType;
  urls: URLSReturnType;
};

const OPEN_EDITION_MINT_SIZE = BigInt("18446744073709551615");
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
  receipt: TransactionReceipt
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
export const convertPremint = (
  premint: PremintSignatureGetResponse["premint"]
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
  collection: PremintSignatureGetResponse["collection"]
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
export const encodePremintForAPI = ({
  tokenConfig,
  ...premint
}: PremintConfig) => ({
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

/**
 * Preminter API to access ZORA Premint functionality.
 * Currently only supports V1 premints.
 */
export class PremintClient {
  network: NetworkConfig;
  chain: Chain;
  apiClient: typeof PremintAPIClient;

  constructor(chain: Chain, apiClient?: typeof PremintAPIClient) {
    this.chain = chain;
    if (!apiClient) {
      apiClient = PremintAPIClient;
    }
    this.apiClient = apiClient;
    const networkConfig = networkConfigByChain[chain.id];
    if (!networkConfig) {
      throw new Error(`Not configured for chain ${chain.id}`);
    }
    this.network = networkConfig;
  }

  /**
   * The premint executor address is deployed to the same address across all chains.
   * Can be overridden as needed by making a parent class.
   *
   * @returns Executor address for premints
   */
  getExecutorAddress() {
    return zoraCreator1155PremintExecutorImplAddress[999];
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

  /**
   * Getter for public client that instantiates a publicClient as needed
   *
   * @param publicClient Optional viem public client
   * @returns Existing public client or makes a new one for the given chain as needed.
   */
  protected getPublicClient(publicClient?: PublicClient): PublicClient {
    if (publicClient) {
      return publicClient;
    }
    return createPublicClient({ chain: this.chain, transport: http() });
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
      chain_name: this.network.zoraBackendChainName,
      collection_address: collection.toLowerCase(),
      uid: uid,
    });

    const convertedPremint = convertPremint(signatureResponse.premint);
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
      publicClient: this.getPublicClient(),
      uid: uid,
      collection: {
        ...signerData.collection,
        contractAdmin: signerData.collection.contractAdmin as Address,
      },
      premintConfig: signerData.premint,
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
    publicClient,
  }: {
    walletClient: WalletClient;
    publicClient: PublicClient;
    uid: number;
    account?: Account | Address;
    collection: Address;
  }) {
    const signatureResponse = await this.apiClient.getSignature({
      chain_name: this.network.zoraBackendChainName,
      collection_address: collection.toLowerCase(),
      uid: uid,
    });

    const signerData = {
      ...signatureResponse,
      collection: convertCollection(signatureResponse.collection),
      premint: {
        ...convertPremint(signatureResponse.premint),
        deleted: true,
      },
    };

    return await this.signAndSubmitPremint({
      walletClient,
      account,
      checkSignature: false,
      verifyingContract: collection,
      publicClient: this.getPublicClient(publicClient),
      uid: uid,
      collection: signerData.collection,
      premintConfig: signerData.premint,
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
    publicClient,
    verifyingContract,
    premintConfig,
    uid,
    account,
    checkSignature,
    collection,
  }: {
    publicClient: PublicClient;
    uid: number;
    walletClient: WalletClient;
    verifyingContract: Address;
    checkSignature: boolean;
    account?: Address | Account;
    premintConfig: PremintConfig;
    collection: PremintSignatureGetResponse["collection"];
  }) {
    if (!account) {
      account = walletClient.account;
    }
    if (!account) {
      throw new Error("No account provided");
    }

    const signature = await walletClient.signTypedData({
      account,
      ...preminterTypedDataDefinition({
        verifyingContract,
        premintConfig,
        chainId: this.chain.id,
      }),
    });

    if (checkSignature) {
      const [isValidSignature] = await publicClient.readContract({
        abi: zoraCreator1155PremintExecutorImplABI,
        address: this.getExecutorAddress(),
        functionName: "isValidSignature",
        args: [convertCollection(collection), premintConfig, signature],
      });
      if (!isValidSignature) {
        throw new Error("Invalid signature");
      }
    }

    const apiData = {
      collection,
      premint: encodePremintForAPI(premintConfig),
      chain_name: this.network.zoraBackendChainName,
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
    publicClient,
    walletClient,
    executionSettings,
    checkSignature = false,
  }: {
    account: Address;
    checkSignature?: boolean;
    walletClient: WalletClient;
    collection: PremintSignatureGetResponse["collection"];
    token: MintArgumentsSettings;
    publicClient?: PublicClient;
    executionSettings?: {
      deleted?: boolean;
      uid?: number;
    };
  }) {
    publicClient = this.getPublicClient(publicClient);

    const newContractAddress = await publicClient.readContract({
      address: this.getExecutorAddress(),
      abi: zoraCreator1155PremintExecutorImplABI,
      functionName: "getContractAddress",
      args: [convertCollection(collection)],
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
        chain_name: this.network.zoraBackendChainName,
        collection_address: newContractAddress.toLowerCase(),
      });
      uid = uidResponse.next_uid;
    }

    if (!uid) {
      throw new Error("UID is missing but required");
    }

    let deleted = executionSettings?.deleted || false;

    const premintConfig = {
      tokenConfig: tokenConfig,
      uid,
      version: 1,
      deleted,
    };

    return await this.signAndSubmitPremint({
      uid,
      verifyingContract: newContractAddress,
      premintConfig,
      checkSignature,
      account,
      publicClient,
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
      chain_name: this.network.zoraBackendChainName,
      collection_address: address,
      uid,
    });
  }

  /**
   * Check user signature for v1
   *
   * @param data Signature data from the API
   * @returns isValid = signature is valid or not, contractAddress = assumed contract address, recoveredSigner = signer from contract
   */
  async isValidSignature({
    data,
    publicClient,
  }: {
    data: PremintSignatureGetResponse;
    publicClient?: PublicClient;
  }): Promise<{
    isValid: boolean;
    contractAddress: Address;
    recoveredSigner: Address;
  }> {
    publicClient = this.getPublicClient(publicClient);

    const [isValid, contractAddress, recoveredSigner] =
      await publicClient.readContract({
        abi: zoraCreator1155PremintExecutorImplABI,
        address: this.getExecutorAddress(),
        functionName: "isValidSignature",
        args: [
          convertCollection(data.collection),
          convertPremint(data.premint),
          data.signature as Hex,
        ],
      });

    return { isValid, contractAddress, recoveredSigner };
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

    return {
      explorer: tokenId
        ? `https://${this.chain.blockExplorers?.default.url}/token/${address}/instance/${tokenId}`
        : null,
      zoraCollect: `https://${
        this.network.isTestnet ? "testnet." : ""
      }zora.co/collect/${
        this.network.zoraPathChainName
      }:${address}/${zoraTokenPath}`,
      zoraManage: `https://${
        this.network.isTestnet ? "testnet." : ""
      }zora.co/collect/${
        this.network.zoraPathChainName
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
  async executePremintWithWallet({
    data,
    account,
    walletClient,
    mintArguments,
    publicClient,
  }: {
    data: PremintSignatureGetResponse;
    walletClient: WalletClient;
    account?: Account | Address;
    mintArguments?: {
      quantityToMint: number;
      mintComment?: string;
    };
    publicClient?: PublicClient;
  }): Promise<ExecutedPremintResponse> {
    publicClient = this.getPublicClient(publicClient);

    if (mintArguments && mintArguments?.quantityToMint < 1) {
      throw new Error("Quantity to mint cannot be below 1");
    }

    const targetAddress = this.getExecutorAddress();
    const numberToMint = BigInt(mintArguments?.quantityToMint || 1);
    const args = [
      convertCollection(data.collection),
      convertPremint(data.premint),
      data.signature as Hex,
      numberToMint,
      mintArguments?.mintComment || "",
    ] as const;

    if (!account) {
      account = walletClient.account;
    }

    if (!account) {
      throw new Error("Wallet not passed in");
    }

    const value = numberToMint * REWARD_PER_TOKEN;

    const { request } = await publicClient.simulateContract({
      account,
      abi: zoraCreator1155PremintExecutorImplABI,
      functionName: "premint",
      value,
      address: targetAddress,
      args,
    });
    const hash = await walletClient.writeContract(request);
    const receipt = await publicClient.waitForTransactionReceipt({ hash });
    const premintedLog = getPremintedLogFromReceipt(receipt);

    return {
      receipt,
      premintedLog,
      urls: this.makeUrls({
        address: premintedLog?.contractAddress,
        tokenId: premintedLog?.tokenId,
      }),
    };
  }
}
