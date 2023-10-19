import { createPublicClient, decodeEventLog, http } from "viem";
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
} from "./wagmiGenerated";
import { foundry, zora, zoraTestnet } from "viem/chains";
import { PremintConfig, preminterTypedDataDefinition } from "./preminter";

export type NetworkConfig = {
  chainId: number;
  zoraPathChainName: string;
  zoraBackendChainName: string;
  isTestnet: boolean;
};

export const enum BackendChainNames {
  ZORA_MAINNET = "ZORA-MAINNET",
  ZORA_TESTNET = "ZORA-TESTNET",
}

const ZORA_API_BASE = "https://api.zora.co/premint/";

export const networkConfigByChain: Record<number, NetworkConfig> = {
  [zora.id]: {
    chainId: zora.id,
    isTestnet: false,
    zoraPathChainName: "zora",
    zoraBackendChainName: BackendChainNames.ZORA_MAINNET,
  },
  [zoraTestnet.id]: {
    chainId: zora.id,
    isTestnet: true,
    zoraPathChainName: "zora",
    zoraBackendChainName: BackendChainNames.ZORA_TESTNET,
  },
  [foundry.id]: {
    chainId: foundry.id,
    isTestnet: true,
    zoraPathChainName: "zora",
    zoraBackendChainName: BackendChainNames.ZORA_TESTNET,
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

const OPEN_EDITION_MINT_SIZE = "18446744073709551615";
const DefaultMintArguments = {
  maxSupply: BigInt(OPEN_EDITION_MINT_SIZE),
  maxTokensPerAddress: 0n,
  pricePerToken: 0n,
  mintDuration: BigInt(60 * 60 * 24 * 7), // 1 week
  mintStart: 0n,
  royaltyMintSchedule: 0,
  royaltyBPS: 1000, // 10%,
};

function getLogFromReceipt(receipt: TransactionReceipt) {
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
 * Premint server response type.
 */
export type PremintResponse = {
  collection: {
    contractAdmin: Address;
    contractURI: string;
    contractName: string;
  };
  premint: {
    tokenConfig: {
      tokenURI: string;
      maxSupply: string;
      maxTokensPerAddress: string;
      pricePerToken: string;
      mintStart: string;
      mintDuration: string;
      royaltyMintSchedule: number;
      royaltyBPS: number;
      royaltyRecipient: Address;
      fixedPriceMinter: Address;
    };
    uid: number;
    version: number;
    deleted: boolean;
  };
  chain_name: BackendChainNames;
  signature: Hex;
};

/**
 * Convert server to on-chain types for a premint
 * @param premint Premint object from the server to convert to one that's compatible with viem
 * @returns Viem type-compatible premint object
 */
export const convertPremint = (premint: PremintResponse["premint"]) => ({
  ...premint,
  tokenConfig: {
    ...premint.tokenConfig,
    maxSupply: BigInt(premint.tokenConfig.maxSupply),
    pricePerToken: BigInt(premint.tokenConfig.pricePerToken),
    mintStart: BigInt(premint.tokenConfig.mintStart),
    mintDuration: BigInt(premint.tokenConfig.mintDuration),
    maxTokensPerAddress: BigInt(premint.tokenConfig.maxTokensPerAddress),
  },
});

/**
 * Convert on-chain types for a premint to a server safe type
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
 * Zora API Server base URL
 */
const ZORA_PREMINT_API_BASE = "https://api.zora.co/premint/";

/**
 * Preminter API to access ZORA Premint functionality.
 * Currently only supports V1 premints.
 */
export class PremintAPI {
  network: NetworkConfig;
  chain: Chain;
  rewardPerToken: bigint;
  constructor(chain: Chain) {
    this.rewardPerToken = BigInt("777000000000000");
    this.chain = chain;
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
   * A simple fetch() wrapper for HTTP gets.
   * Can be overridden as needed.
   *
   * @param path Path to run HTTP JSON get against
   * @returns JSON object response
   * @throws Error when HTTP response fails
   */
  async get(path: string) {
    const response = await fetch(path, { method: "GET" });
    if (response.status !== 200) {
      throw new Error(`Invalid response, status ${response.status}`);
    }
    return await response.json();
  }

  /**
   * A simple fetch() wrapper for HTTP post.
   * Can be overridden as needed.
   *
   * @param path Path to run HTTP JSON POST against
   * @param data Data to POST to the server, converted to JSON
   * @returns JSON object response
   * @throws Error when HTTP response fails
   */
  async post(path: string, data: any) {
    const response = await fetch(path, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        accept: "application/json",
      },
      body: JSON.stringify(data),
    });
    if (response.status !== 200) {
      throw new Error(`Bad response: ${response.status}`);
    }
    return await response.json();
  }

  /**
   * Getter for public client that instantiates a publicClient as needed
   *
   * @param publicClient Optional viem public client
   * @returns Existing public client or makes a new one for the given chain as needed.
   */
  getPublicClient(publicClient?: PublicClient): PublicClient {
    if (publicClient) {
      return publicClient;
    }
    return createPublicClient({ chain: this.chain, transport: http() });
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
    collection: PremintResponse["collection"];
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
      args: [collection],
    });

    const tokenConfig = {
      ...DefaultMintArguments,
      fixedPriceMinter: this.getFixedPriceMinterAddress(),
      royaltyRecipient: account,
      ...token,
    };

    let uid = executionSettings?.uid;
    if (!uid) {
      const uidResponse = await this.get(
        `${ZORA_API_BASE}signature/${
          this.network.zoraBackendChainName
        }/${newContractAddress.toLowerCase()}/next_uid`
      );
      uid = uidResponse["next_uid"];
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

    const signature = await walletClient.signTypedData({
      account,
      ...preminterTypedDataDefinition({
        verifyingContract: newContractAddress,
        premintConfig,
        chainId: this.chain.id,
      }),
    });

    if (checkSignature) {
      const [isValidSignature] = await publicClient.readContract({
        abi: zoraCreator1155PremintExecutorImplABI,
        address: this.getExecutorAddress(),
        functionName: "isValidSignature",
        args: [collection, premintConfig, signature],
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

    const premint = await this.post(`${ZORA_API_BASE}signature`, apiData);

    return {
      url: `https://${
        this.network.isTestnet ? "testnet." : ""
      }zora.co/collect:${
        this.network.zoraPathChainName
      }:${newContractAddress}/premint-${uid}`,
      uid,
      newContractAddress,
      premint,
    };
  }

  /**
   * Fetches given premint data from the ZORA API.
   *
   * @param address Address for the premint contract
   * @param uid UID for the desired premint
   * @returns PremintResponse of premint data from the API
   */
  async getPremintData(address: string, uid: number): Promise<PremintResponse> {
    const response = await this.get(
      `${ZORA_PREMINT_API_BASE}signature/${this.network.zoraBackendChainName}/${address}/${uid}`
    );
    return response as PremintResponse;
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
    data: PremintResponse;
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
        args: [data.collection, convertPremint(data.premint), data.signature],
      });

    return { isValid, contractAddress, recoveredSigner };
  }

  /**
   * Execute premint
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
    data: PremintResponse;
    walletClient: WalletClient;
    account?: Account | Address;
    mintArguments?: {
      quantityToMint: number;
      mintComment?: string;
    };
    publicClient?: PublicClient;
  }) {
    publicClient = this.getPublicClient(publicClient);

    if (mintArguments && mintArguments?.quantityToMint < 1) {
      throw new Error("Quantity to mint cannot be below 1");
    }

    const targetAddress = this.getExecutorAddress();
    const numberToMint = BigInt(mintArguments?.quantityToMint || 1);
    const args = [
      data.collection,
      convertPremint(data.premint),
      data.signature,
      numberToMint,
      mintArguments?.mintComment || "",
    ] as const;

    if (!account) {
      account = walletClient.account;
    }

    if (!account) {
      throw new Error("Wallet not passed in");
    }

    const value = numberToMint * this.rewardPerToken;

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
    const log = getLogFromReceipt(receipt);

    return {
      receipt,
      log,
      zoraUrl: log
        ? `https://${this.network.isTestnet ? "testnet." : ""}zora.co/collect/${
            this.network.zoraPathChainName
          }:${log.contractAddress}/${log.tokenId}`
        : null,
    };
  }
}
