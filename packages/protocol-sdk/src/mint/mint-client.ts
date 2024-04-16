import {
  Address,
  Chain,
  PublicClient,
  createPublicClient,
  encodeAbiParameters,
  parseAbiParameters,
  zeroAddress,
  http,
  Account,
  SimulateContractParameters,
} from "viem";
import { IHttpClient } from "../apis/http-api-base";
import { MintAPIClient, SalesConfigAndTokenInfo } from "./mint-api-client";
import {
  zoraCreator1155ImplABI,
  zoraCreatorFixedPriceSaleStrategyAddress,
} from "@zoralabs/protocol-deployments";
import { GenericTokenIdTypes } from "src/types";
import { zora721Abi } from "src/constants";
import { makeSimulateContractParamaters } from "src/utils";

class MintError extends Error {}
class MintInactiveError extends Error {}

export const Errors = {
  MintError,
  MintInactiveError,
};

type MintArguments = {
  quantityToMint: number;
  mintComment?: string;
  mintReferral?: Address;
  mintToAddress: Address;
};

class MintClient {
  readonly apiClient: MintAPIClient;
  readonly publicClient: PublicClient;

  constructor(
    chain: Chain,
    publicClient?: PublicClient,
    httpClient?: IHttpClient,
  ) {
    this.apiClient = new MintAPIClient(chain.id, httpClient);
    this.publicClient =
      publicClient || createPublicClient({ chain, transport: http() });
  }

  /**
   * Returns the parameters needed to prepare a transaction mint a token.
   * @param param0.minterAccount The account that will mint the token.
   * @param param0.mintable The mintable token to mint.
   * @param param0.mintArguments The arguments for the mint (mint recipient, comment, mint referral, quantity to mint)
   * @returns
   */
  async makePrepareMintTokenParams({
    ...rest
  }: {
    minterAccount: Address | Account;
    tokenAddress: Address;
    tokenId?: GenericTokenIdTypes;
    mintArguments: MintArguments;
  }) {
    return makePrepareMintTokenParams({
      ...rest,
      apiClient: this.apiClient,
      publicClient: this.publicClient,
    });
  }
}

/**
 * Creates a new MintClient.
 * @param param0.chain The chain to use for the mint client.
 * @param param0.publicClient Optional viem public client
 * @param param0.httpClient Optional http client to override post, get, and retry methods
 * @returns
 */
export function createMintClient({
  chain,
  publicClient,
  httpClient,
}: {
  chain: Chain;
  publicClient?: PublicClient;
  httpClient?: IHttpClient;
}) {
  return new MintClient(chain, publicClient, httpClient);
}

export type TMintClient = ReturnType<typeof createMintClient>;

async function makePrepareMintTokenParams({
  publicClient,
  apiClient,
  tokenId,
  tokenAddress,
  ...rest
}: {
  publicClient: PublicClient;
  minterAccount: Address | Account;
  tokenId?: GenericTokenIdTypes;
  tokenAddress: Address;
  mintArguments: MintArguments;
  apiClient: MintAPIClient;
}): Promise<
  SimulateContractParameters<any, any, any, any, any, Account | Address>
> {
  const salesConfigAndTokenInfo = await apiClient.getSalesConfigAndTokenInfo({
    tokenId,
    tokenAddress,
  });

  if (tokenId === undefined) {
    return makePrepareMint721TokenParams({
      salesConfigAndTokenInfo,
      tokenAddress,
      ...rest,
    });
  }

  return makePrepareMint1155TokenParams({
    salesConfigAndTokenInfo,
    tokenAddress,
    tokenId,
    ...rest,
  });
}

async function makePrepareMint721TokenParams({
  tokenAddress,
  salesConfigAndTokenInfo,
  minterAccount,
  mintArguments,
}: {
  tokenAddress: Address;
  salesConfigAndTokenInfo: SalesConfigAndTokenInfo;
  minterAccount: Address | Account;
  mintArguments: MintArguments;
}) {
  const mintValue = getMintCosts({
    salesConfigAndTokenInfo,
    quantityToMint: BigInt(mintArguments.quantityToMint),
  }).totalCost;

  return makeSimulateContractParamaters({
    abi: zora721Abi,
    address: tokenAddress,
    account: minterAccount,
    functionName: "mintWithRewards",
    value: mintValue,
    args: [
      mintArguments.mintToAddress,
      BigInt(mintArguments.quantityToMint),
      mintArguments.mintComment || "",
      mintArguments.mintReferral || zeroAddress,
    ],
  });
}

export type MintCosts = {
  mintFee: bigint;
  tokenPurchaseCost: bigint;
  totalCost: bigint;
};

export function getMintCosts({
  salesConfigAndTokenInfo,
  quantityToMint,
}: {
  salesConfigAndTokenInfo: SalesConfigAndTokenInfo;
  quantityToMint: bigint;
}): MintCosts {
  const mintFeeForTokens =
    salesConfigAndTokenInfo.mintFeePerQuantity * quantityToMint;
  const tokenPurchaseCost =
    BigInt(salesConfigAndTokenInfo.fixedPrice.pricePerToken) * quantityToMint;

  return {
    mintFee: mintFeeForTokens,
    tokenPurchaseCost,
    totalCost: mintFeeForTokens + tokenPurchaseCost,
  };
}

async function makePrepareMint1155TokenParams({
  tokenId,
  salesConfigAndTokenInfo,
  minterAccount,
  tokenAddress,
  mintArguments,
}: {
  salesConfigAndTokenInfo: SalesConfigAndTokenInfo;
  tokenId: GenericTokenIdTypes;
  minterAccount: Address | Account;
  tokenAddress: Address;
  mintArguments: MintArguments;
}) {
  const mintQuantity = BigInt(mintArguments.quantityToMint);

  const mintValue = getMintCosts({
    salesConfigAndTokenInfo,
    quantityToMint: mintQuantity,
  }).totalCost;

  return makeSimulateContractParamaters({
    abi: zoraCreator1155ImplABI,
    functionName: "mintWithRewards",
    account: minterAccount,
    value: mintValue,
    address: tokenAddress,
    /* args: minter, tokenId, quantity, minterArguments, mintReferral */
    args: [
      (salesConfigAndTokenInfo?.fixedPrice.address ||
        zoraCreatorFixedPriceSaleStrategyAddress[999]) as Address,
      BigInt(tokenId),
      mintQuantity,
      encodeAbiParameters(parseAbiParameters("address, string"), [
        mintArguments.mintToAddress,
        mintArguments.mintComment || "",
      ]),
      mintArguments.mintReferral || zeroAddress,
    ],
  });
}
