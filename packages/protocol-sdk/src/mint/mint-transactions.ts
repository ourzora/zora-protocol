import {
  Address,
  encodeAbiParameters,
  parseAbiParameters,
  zeroAddress,
  Account,
  SimulateContractParameters,
} from "viem";
import {
  erc20MinterABI,
  zoraCreator1155ImplABI,
} from "@zoralabs/protocol-deployments";
import { zora721Abi } from "src/constants";
import {
  GenericTokenIdTypes,
  SimulateContractParametersWithAccount,
} from "src/types";
import { makeContractParameters, mintRecipientOrAccount } from "src/utils";
import { MintCosts, SaleStrategies, isErc20SaleStrategy } from "./types";
import { MakeMintParametersArgumentsBase } from "./types";

import { contractSupportsNewMintFunction } from "./utils";
import { OnchainSalesConfigAndTokenInfo } from "./types";

export function makeOnchainMintCall({
  token,
  mintParams,
}: {
  token: OnchainSalesConfigAndTokenInfo;
  mintParams: Omit<MakeMintParametersArgumentsBase, "tokenContract">;
}): SimulateContractParametersWithAccount {
  if (token.mintType === "721") {
    return makePrepareMint721TokenParams({
      salesConfigAndTokenInfo: token,
      tokenContract: token.contract.address,
      ...mintParams,
    });
  }

  return makePrepareMint1155TokenParams({
    salesConfigAndTokenInfo: token,
    tokenContract: token.contract.address,
    tokenId: token.tokenId!,
    ...mintParams,
  });
}

export type MintableParameters = Pick<
  OnchainSalesConfigAndTokenInfo,
  "contractVersion" | "mintFeePerQuantity" | "salesConfig"
>;

export function makePrepareMint1155TokenParams({
  tokenContract: tokenContract,
  tokenId,
  salesConfigAndTokenInfo,
  minterAccount,
  mintComment,
  mintReferral,
  mintRecipient,
  quantityToMint,
}: {
  salesConfigAndTokenInfo: MintableParameters;
  tokenId: GenericTokenIdTypes;
} & Pick<
  MakeMintParametersArgumentsBase,
  | "minterAccount"
  | "tokenContract"
  | "mintComment"
  | "mintReferral"
  | "quantityToMint"
  | "mintRecipient"
>): SimulateContractParameters<any, any, any, any, any, Address | Account> {
  const mintQuantity = BigInt(quantityToMint || 1);

  const mintTo = mintRecipientOrAccount({ mintRecipient, minterAccount });

  const saleType = salesConfigAndTokenInfo.salesConfig.saleType;

  if (saleType === "fixedPrice") {
    return makeEthMintCall({
      mintComment,
      minterAccount,
      mintQuantity,
      mintReferral,
      mintTo,
      salesConfigAndTokenInfo,
      tokenContract,
      tokenId,
    });
  }

  if (saleType === "erc20") {
    return makeContractParameters({
      abi: erc20MinterABI,
      functionName: "mint",
      account: minterAccount,
      address: salesConfigAndTokenInfo.salesConfig.address,
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

  throw new Error("Unsupported sale type");
}

function makePrepareMint721TokenParams({
  salesConfigAndTokenInfo,
  minterAccount,
  tokenContract,
  mintComment,
  mintReferral,
  mintRecipient,
  quantityToMint,
}: {
  salesConfigAndTokenInfo: MintableParameters;
} & Pick<
  MakeMintParametersArgumentsBase,
  | "minterAccount"
  | "tokenContract"
  | "mintComment"
  | "mintReferral"
  | "quantityToMint"
  | "mintRecipient"
>): SimulateContractParametersWithAccount {
  const actualQuantityToMint = BigInt(quantityToMint || 1);
  const mintValue = parseMintCosts({
    mintFeePerQuantity: salesConfigAndTokenInfo.mintFeePerQuantity,
    salesConfig: salesConfigAndTokenInfo.salesConfig,
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

function makeEthMintCall({
  tokenContract,
  tokenId,
  salesConfigAndTokenInfo,
  minterAccount,
  mintComment,
  mintReferral,
  mintQuantity,
  mintTo,
}: {
  minterAccount: Account | Address;
  tokenContract: Address;
  mintTo: Address;
  salesConfigAndTokenInfo: MintableParameters;
  tokenId: GenericTokenIdTypes;
  mintQuantity: bigint;
  mintComment?: string;
  mintReferral?: Address;
}): SimulateContractParametersWithAccount {
  const mintValue = parseMintCosts({
    mintFeePerQuantity: salesConfigAndTokenInfo.mintFeePerQuantity,
    salesConfig: salesConfigAndTokenInfo.salesConfig,
    quantityToMint: mintQuantity,
  }).totalCostEth;

  const minterArguments = encodeAbiParameters(
    parseAbiParameters("address, string"),
    [mintTo, mintComment || ""],
  );

  // if based on contract version it has the new mint function,
  // call the new mint function.
  if (
    contractSupportsNewMintFunction(salesConfigAndTokenInfo.contractVersion)
  ) {
    return makeContractParameters({
      abi: zoraCreator1155ImplABI,
      functionName: "mint",
      account: minterAccount,
      value: mintValue,
      address: tokenContract,
      args: [
        salesConfigAndTokenInfo.salesConfig.address,
        BigInt(tokenId),
        mintQuantity,
        mintReferral ? [mintReferral] : [],
        minterArguments,
      ],
    });
  }

  // otherwise call the deprecated mint function
  return makeContractParameters({
    abi: zoraCreator1155ImplABI,
    functionName: "mintWithRewards",
    account: minterAccount,
    value: mintValue,
    address: tokenContract,
    /* args: minter, tokenId, quantity, minterArguments, mintReferral */
    args: [
      salesConfigAndTokenInfo.salesConfig.address,
      BigInt(tokenId),
      mintQuantity,
      minterArguments,
      mintReferral || zeroAddress,
    ],
  });
}

export function parseMintCosts({
  salesConfig,
  mintFeePerQuantity,
  quantityToMint,
}: {
  salesConfig: SaleStrategies;
  mintFeePerQuantity: bigint;
  quantityToMint: bigint;
}): MintCosts {
  const mintFeeForTokens = mintFeePerQuantity * quantityToMint;

  const tokenPurchaseCost = BigInt(salesConfig.pricePerToken) * quantityToMint;

  const totalPurchaseCostCurrency = isErc20SaleStrategy(salesConfig)
    ? salesConfig.currency
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
