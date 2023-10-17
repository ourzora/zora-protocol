import { createPublicClient, http } from "viem";
import type {
  Account,
  Address,
  Chain,
  Hex,
  PublicClient,
  WalletClient,
} from "viem";
import {
  zoraCreator1155PremintExecutorImplABI,
  zoraCreator1155PremintExecutorImplAddress,
  zoraCreatorFixedPriceSaleStrategyAddress,
} from "./wagmiGenerated";
import { foundry, zora, zoraTestnet } from "viem/chains";
import { PremintConfig, preminterTypedDataDefinition } from "./preminter";

type NetworkConfig = {
  chainId: number;
  zoraPathChainName: string;
  zoraBackendChainName: string;
  isTestnet: boolean;
};

enum BackendChainNames {
  ZORA_MAINNET = "ZORA-MAINNET",
  ZORA_TESTNET = "ZORA-TESTNET",
}

const ZORA_API_BASE = "https://api.zora.co/premint/";

const networkConfigByChain: Record<number, NetworkConfig> = {
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
  }
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

type PremintResponse = {
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

const convertPremint = (premint: PremintResponse["premint"]) => ({
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

const encodePremintForAPI = ({ tokenConfig, ...premint }: PremintConfig) => ({
  ...premint,
  tokenConfig: {
    ...tokenConfig,
    maxSupply: tokenConfig.maxSupply.toString(),
    pricePerToken: tokenConfig.maxSupply.toString(),
    mintStart: tokenConfig.mintStart.toString(),
    mintDuration: tokenConfig.mintDuration.toString(),
    maxTokensPerAddress: tokenConfig.maxTokensPerAddress.toString(),
  },
});

const ZORA_PREMINT_API_BASE = "https://api.zora.co/premint/";

export class PreminterAPI {
  network: NetworkConfig;
  chain: Chain;
  mintFee: BigInt;
  constructor(chain: Chain) {
    this.chain = chain;
    const networkConfig = networkConfigByChain[chain.id];
    if (!networkConfig) {
      throw new Error(`Not configured for chain ${chain.id}`);
    }
    this.network = networkConfig;
    this.mintFee = BigInt("777000000000000");
  }

  async get(path: string) {
    const response = await fetch(path, { method: "GET" });
    return await response.json();
  }

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

  async createPremint({
    account,
    collection,
    mint,
    publicClient,
    walletClient,
    executionSettings,
    checkSignature = true,
  }: {
    account: Address;
    checkSignature?: boolean;
    walletClient: WalletClient;
    collection: PremintResponse["collection"];
    mint: MintArgumentsSettings;
    publicClient?: PublicClient;
    executionSettings?: {
      deleted?: boolean;
      uid?: number;
    };
  }) {
    const executor = (zoraCreator1155PremintExecutorImplAddress as any)[
      this.chain.id
    ] as Address;

    if (!publicClient) {
      publicClient = createPublicClient({
        chain: this.chain,
        transport: http(),
      });
    }
    const newContractAddress = await publicClient.readContract({
      address: executor,
      abi: zoraCreator1155PremintExecutorImplABI,
      functionName: "getContractAddress",
      args: [collection],
    });

    const tokenConfig = {
      ...DefaultMintArguments,
      fixedPriceMinter: (zoraCreatorFixedPriceSaleStrategyAddress as any)[
        this.chain.id
      ] as Address,
      royaltyRecipient: account,
      ...mint,
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
    let deleted = executionSettings?.deleted || false;

    const premintConfig = {
      tokenConfig: tokenConfig,
      uid: uid!,
      version: 1,
      deleted,
    };

    console.log('chainid', this.chain.id);
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
        address: executor,
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

  async getPremintData(address: string, uid: number): Promise<PremintResponse> {
    const response = await this.get(
      `${ZORA_PREMINT_API_BASE}signature/${this.network.zoraBackendChainName}/${address}/${uid}`
    );
    return response as PremintResponse;
  }

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
    mintArguments: {
      quantityToMint: bigint;
      mintComment: string;
    };
    publicClient?: PublicClient;
  }) {
    const targetAddress: Address = (
      zoraCreator1155PremintExecutorImplAddress as any
    )[this.network.chainId];
    const args = [
      data.collection,
      convertPremint(data.premint),
      data.signature,
      mintArguments.quantityToMint,
      mintArguments.mintComment,
    ] as const;

    if (!account) {
      account = walletClient.account!;
    }

    if (publicClient) {
      const { request } = await publicClient.simulateContract({
        account,
        abi: zoraCreator1155PremintExecutorImplABI,
        functionName: "premint",
        address: targetAddress,
        args,
      });
      console.log({request})
      return await walletClient.writeContract(request);
    }

    return await walletClient.writeContract({
      abi: zoraCreator1155PremintExecutorImplABI,
      account,
      chain: this.chain,
      functionName: "premint",
      address: targetAddress,
      args,
    });
  }
}
