import {
  Address,
  encodeAbiParameters,
  parseAbiParameters,
  zeroAddress,
  Account,
  SimulateContractParameters,
  erc20Abi,
} from "viem";
import {
  erc20MinterABI,
  erc20MinterAddress,
  zoraCreator1155ImplABI,
  zoraCreatorFixedPriceSaleStrategyAddress,
} from "@zoralabs/protocol-deployments";
import { zora721Abi } from "src/constants";
import { GenericTokenIdTypes } from "src/types";
import {
  makeContractParameters,
  PublicClient,
  mintRecipientOrAccount,
} from "src/utils";
import {
  IMintGetter,
  SalesConfigAndTokenInfo,
  isErc20SaleStrategy,
} from "./types";
import {
  MakeMintParametersArguments,
  MakeMintParametersArgumentsBase,
  Make1155MintArguments,
  MakePremintMintParametersArguments,
  Make721MintArguments,
  GetMintCostsParameters,
  isOnChainMint,
  is1155Mint,
} from "./types";
import { collectPremint } from "src/premint/premint-client";
import { IPremintGetter } from "src/premint/premint-api-client";
import { getPremintMintCostsWithUnknownTokenPrice } from "src/premint/preminter";

class MintError extends Error {}
class MintInactiveError extends Error {}

export const Errors = {
  MintError,
  MintInactiveError,
};

export class MintClient {
  private readonly chainId: number;
  private readonly publicClient: PublicClient;
  private readonly mintGetter: IMintGetter;
  private readonly premintGetter: IPremintGetter;

  constructor({
    chainId,
    publicClient,
    premintGetter,
    mintGetter,
  }: {
    chainId: number;
    publicClient: PublicClient;
    premintGetter: IPremintGetter;
    mintGetter: IMintGetter;
  }) {
    this.chainId = chainId;
    this.publicClient = publicClient;
    this.mintGetter = mintGetter;
    this.premintGetter = premintGetter;
  }

  /**
   * Returns the parameters needed to prepare a transaction mint a token.
   * Works with premint, onchain 1155, and onchain 721.
   *
   * @param parameters - Parameters for collecting the token {@link MakeMintParametersArguments}
   * @returns Parameters for simulating/executing the mint transaction
   */
  async mint(parameters: MakeMintParametersArguments) {
    return mint({
      parameters,
      chainId: this.chainId,
      publicClient: this.publicClient,
      mintGetter: this.mintGetter,
      premintGetter: this.premintGetter,
    });
  }

  /**
   * Gets the costs to mint the quantity of tokens specified for a mint.
   * @param parameters - Parameters for the mint {@link GetMintCostsParameters}
   * @returns Costs to mint the quantity of tokens specified
   */
  async getMintCosts(parameters: GetMintCostsParameters): Promise<MintCosts> {
    return getMintCosts({
      ...parameters,
      mintGetter: this.mintGetter,
      premintGetter: this.premintGetter,
      publicClient: this.publicClient,
    });
  }
}

function isPremintCollect(
  parameters: MakeMintParametersArguments,
): parameters is MakePremintMintParametersArguments {
  return parameters.mintType === "premint";
}

function is721Collect(
  parameters: MakeMintParametersArguments,
): parameters is Make721MintArguments {
  return parameters.mintType === "721";
}

async function mint({
  parameters,
  chainId,
  publicClient,
  mintGetter,
  premintGetter,
}: {
  parameters: MakeMintParametersArguments;
  publicClient: PublicClient;
  mintGetter: IMintGetter;
  premintGetter: IPremintGetter;
  chainId: number;
}) {
  if (isPremintCollect(parameters)) {
    return {
      parameters: await collectPremint({
        ...parameters,
        premintGetter: premintGetter,
        publicClient,
      }),
    };
  }

  return {
    parameters: await collectOnchain({
      ...parameters,
      mintGetter: mintGetter,
      chainId,
    }),
  };
}

export function requestErc20ApprovalForMint({
  account,
  tokenAddress,
  quantityErc20,
  erc20MinterAddress,
}: {
  account: Account | Address;
  tokenAddress: Address;
  quantityErc20: bigint;
  erc20MinterAddress: Address;
}) {
  return makeContractParameters({
    abi: erc20Abi,
    address: tokenAddress,
    account,
    functionName: "approve",
    args: [erc20MinterAddress, quantityErc20],
  });
}

export async function getNecessaryErc20Approval({
  chainId,
  account,
  tokenAddress,
  quantityErc20,
  publicClient,
}: {
  chainId: number;
  account: Account | Address;
  tokenAddress: Address;
  quantityErc20: bigint;
  publicClient: PublicClient;
}) {
  const destination =
    erc20MinterAddress[chainId as keyof typeof erc20MinterAddress];
  const allowance = await publicClient.readContract({
    abi: erc20Abi,
    address: tokenAddress,
    functionName: "allowance",
    account,
    args: [
      destination,
      erc20MinterAddress[chainId as keyof typeof erc20MinterAddress],
    ],
  });

  if (allowance < quantityErc20) {
    return requestErc20ApprovalForMint({
      erc20MinterAddress: destination,
      account,
      tokenAddress,
      quantityErc20: quantityErc20 - allowance,
    });
  }

  return undefined;
}

export async function collectOnchain({
  chainId,
  mintGetter,
  ...parameters
}: (Make1155MintArguments | Make721MintArguments) & {
  mintGetter: IMintGetter;
  chainId: number;
}): Promise<
  SimulateContractParameters<any, any, any, any, any, Account | Address>
> {
  const { tokenContract: tokenContract, saleType } = parameters;
  const tokenId = is1155Mint(parameters) ? parameters.tokenId : undefined;
  const salesConfigAndTokenInfo = await mintGetter.getSalesConfigAndTokenInfo({
    tokenId,
    tokenAddress: tokenContract,
    saleType,
  });

  if (is721Collect(parameters)) {
    return makePrepareMint721TokenParams({
      salesConfigAndTokenInfo,
      ...parameters,
    });
  }

  return makePrepareMint1155TokenParams({
    salesConfigAndTokenInfo,
    chainId,
    ...parameters,
  });
}

async function makePrepareMint721TokenParams({
  salesConfigAndTokenInfo,
  minterAccount,
  tokenContract,
  mintComment,
  mintReferral,
  mintRecipient,
  quantityToMint,
}: {
  salesConfigAndTokenInfo: SalesConfigAndTokenInfo;
} & Pick<
  MakeMintParametersArgumentsBase,
  | "minterAccount"
  | "tokenContract"
  | "mintComment"
  | "mintReferral"
  | "quantityToMint"
  | "mintRecipient"
>) {
  const actualQuantityToMint = BigInt(quantityToMint || 1);
  const mintValue = parseMintCosts({
    salesConfigAndTokenInfo,
    quantityToMint: actualQuantityToMint,
  }).totalCostEth;

  return makeContractParameters({
    abi: zora721Abi,
    address: tokenContract,
    account: minterAccount,
    functionName: "mintWithRewards",
    value: mintValue,
    args: [
      mintRecipientOrAccount({ mintRecipient, minterAccount }),
      actualQuantityToMint,
      mintComment || "",
      mintReferral || zeroAddress,
    ],
  });
}

export type MintCosts = {
  /** The total of the mint fee, in eth */
  mintFee: bigint;
  /** If it is a paid or erc20 mint, the total price of the paid or erc20 mint in eth or erc20 value correspondingly. */
  totalPurchaseCost: bigint;
  /** If it is an erc20 mint, the erc20 address */
  totalPurchaseCostCurrency?: Address;
  /** The total cost in eth (mint fee + purchase cost) to mint */
  totalCostEth: bigint;
};

export function parseMintCosts({
  salesConfigAndTokenInfo,
  quantityToMint,
}: {
  salesConfigAndTokenInfo: SalesConfigAndTokenInfo;
  quantityToMint: bigint;
}): MintCosts {
  const mintFeeForTokens =
    salesConfigAndTokenInfo.mintFeePerQuantity * quantityToMint;

  const tokenPurchaseCost =
    BigInt(salesConfigAndTokenInfo.salesConfig.pricePerToken) * quantityToMint;

  const totalPurchaseCostCurrency = isErc20SaleStrategy(
    salesConfigAndTokenInfo.salesConfig,
  )
    ? salesConfigAndTokenInfo.salesConfig.currency
    : undefined;

  const totalPurchaseCostEth = totalPurchaseCostCurrency
    ? 0n
    : tokenPurchaseCost;

  return {
    mintFee: mintFeeForTokens,
    totalPurchaseCost: tokenPurchaseCost,
    totalPurchaseCostCurrency,
    totalCostEth: mintFeeForTokens + totalPurchaseCostEth,
  };
}

export async function getMintCosts(
  params: GetMintCostsParameters & {
    mintGetter: IMintGetter;
    premintGetter: IPremintGetter;
    publicClient: PublicClient;
  },
) {
  const { quantityMinted: quantityToMint, collection, publicClient } = params;
  if (isOnChainMint(params)) {
    const tokenId = is1155Mint(params) ? params.tokenId : undefined;
    const salesConfigAndTokenInfo =
      await params.mintGetter.getSalesConfigAndTokenInfo({
        tokenId,
        tokenAddress: collection,
      });

    return parseMintCosts({
      salesConfigAndTokenInfo,
      quantityToMint: BigInt(quantityToMint),
    });
  }

  return getPremintMintCostsWithUnknownTokenPrice({
    premintGetter: params.premintGetter,
    publicClient: publicClient,
    quantityToMint: BigInt(quantityToMint),
    uid: params.uid,
    tokenContract: collection,
  });
}

export function makePrepareMint1155TokenParams({
  tokenContract: tokenContract,
  tokenId,
  salesConfigAndTokenInfo,
  minterAccount,
  mintComment,
  mintReferral,
  mintRecipient,
  quantityToMint,
  chainId,
}: {
  salesConfigAndTokenInfo: SalesConfigAndTokenInfo;
  chainId: number;
  tokenId: GenericTokenIdTypes;
} & Pick<
  MakeMintParametersArgumentsBase,
  | "minterAccount"
  | "tokenContract"
  | "mintComment"
  | "mintReferral"
  | "quantityToMint"
  | "mintRecipient"
>) {
  const mintQuantity = BigInt(quantityToMint || 1);

  const mintTo = mintRecipientOrAccount({ mintRecipient, minterAccount });

  const saleType = salesConfigAndTokenInfo.salesConfig.saleType;

  if (saleType === "fixedPrice") {
    const mintValue = parseMintCosts({
      salesConfigAndTokenInfo,
      quantityToMint: mintQuantity,
    }).totalCostEth;

    return makeContractParameters({
      abi: zoraCreator1155ImplABI,
      functionName: "mintWithRewards",
      account: minterAccount,
      value: mintValue,
      address: tokenContract,
      /* args: minter, tokenId, quantity, minterArguments, mintReferral */
      args: [
        (salesConfigAndTokenInfo.salesConfig.address ||
          zoraCreatorFixedPriceSaleStrategyAddress[
            chainId as keyof typeof zoraCreatorFixedPriceSaleStrategyAddress
          ]) as Address,
        BigInt(tokenId),
        mintQuantity,
        encodeAbiParameters(parseAbiParameters("address, string"), [
          mintTo,
          mintComment || "",
        ]),
        mintReferral || zeroAddress,
      ],
    });
  }

  if (saleType === "erc20") {
    return makeContractParameters({
      abi: erc20MinterABI,
      functionName: "mint",
      account: minterAccount,
      address: (salesConfigAndTokenInfo?.salesConfig.address ||
        erc20MinterAddress[
          chainId as keyof typeof erc20MinterAddress
        ]) as Address,
      /* args: mintTo, quantity, tokenAddress, tokenId, totalValue, currency, mintReferral, comment */
      args: [
        mintTo,
        mintQuantity,
        tokenContract,
        BigInt(tokenId),
        salesConfigAndTokenInfo.salesConfig.pricePerToken * mintQuantity,
        salesConfigAndTokenInfo.salesConfig.currency,
        mintReferral || zeroAddress,
        mintComment || "",
      ],
    });
  }

  throw new MintError("Unsupported sale type");
}
