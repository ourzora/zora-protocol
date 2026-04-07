import {
  IPremintGetter,
  PremintAPIClient,
} from "src/premint/premint-api-client";
import {
  ContractInfo,
  Erc20Approval,
  GetMintCostsParameterArguments,
  GetMintParameters,
  IOnchainMintGetter,
  MintParametersBase,
  MintableReturn,
  OnchainSalesConfigAndTokenInfo,
  PremintSalesConfigAndTokenInfo,
  PrepareMint,
  is1155Mint,
  isOnChainMint,
  GetMintableReturn,
  GetMintsOfContractParameters,
  WithPublicClientAndRequiredGetters,
} from "./types";
import { Address, zeroAddress } from "viem";
import {
  getPremintMintCostsWithUnknownTokenPrice,
  getPremintMintFee,
} from "src/premint/preminter";
import {
  PremintFromApi,
  isPremintConfigV1,
  isPremintConfigV2,
} from "src/premint/conversions";
import { makeOnchainMintCall, parseMintCosts } from "./mint-transactions";
import { buildPremintMintCall } from "src/premint/premint-client";
import { AllowListEntry } from "src/allow-list/types";
import { Concrete } from "src/utils";
import { parseAndFilterTokenQueryResult } from "./strategies-parsing";
import { SubgraphMintGetter } from "./subgraph-mint-getter";

/**
 * Gets an 1155, 721, or premint, and returns both information about it, and a function
 * that can be used to build a mint transaction for a quantity of items to mint.
 * @param parameters - Token to get {@link GetMintParameters}
 * @returns Information about the mint and a function to build a mint transaction {@link MintableReturn}
 */
export async function getToken(
  params: GetMintParameters,
): Promise<MintableReturn> {
  const { premintGetter, publicClient } = params;
  const chainId = publicClient.chain.id;
  if (isOnChainMint(params)) {
    const tokenId = is1155Mint(params) ? params.tokenId : undefined;
    const blockTime = (await publicClient.getBlock()).timestamp;
    const mintGetterOrDefault =
      params.mintGetter ?? new SubgraphMintGetter(chainId);
    const result = await mintGetterOrDefault.getMintable({
      tokenId,
      tokenAddress: params.tokenContract,
    });

    const token = parseAndFilterTokenQueryResult({
      token: result,
      tokenId,
      preferredSaleType: params.preferredSaleType,
      blockTime,
    });

    return toMintableReturn(token, chainId);
  }

  const premintGetterOrDefault = premintGetter ?? new PremintAPIClient(chainId);
  const premint = await premintGetterOrDefault.get({
    collectionAddress: params.tokenContract,
    uid: params.uid,
  });

  const mintFee = await getPremintMintFee({
    publicClient,
    tokenContract: params.tokenContract,
  });

  return toPremintMintReturn({ premint, mintFee });
}
export async function getPremintsOfCollectionWithTokenIds({
  premintGetter,
  mintGetter,
  tokenContract,
}: {
  premintGetter: IPremintGetter;
  mintGetter: IOnchainMintGetter;
  tokenContract: Address;
}) {
  const { collection, premints } = await premintGetter.getOfCollection({
    collectionAddress: tokenContract,
  });

  const premintUidsAndTokenIds = await mintGetter.getContractPremintTokenIds({
    tokenAddress: tokenContract,
  });

  const premintsWithTokenId = premints.map((premint) => ({
    ...premint,
    tokenId: premintUidsAndTokenIds.find(
      ({ uid }) => uid === premint.premint.premintConfig.uid,
    )?.tokenId,
  }));

  return {
    collection: collection,
    premints: premintsWithTokenId,
  };
}

/**
 * Gets onchain and premint tokens of an 1155 contract. For each token returns both information about it, and a function
 * that can be used to build a mint transaction for a quantity of items to mint.
 * @param parameters - Contract address to get tokens for {@link GetMintsOfContractParameters}
 * @returns Array of tokens, each containing information about the token and a function to build a mint transaction.
 */
export async function getTokensOfContract({
  mintGetter,
  premintGetter,
  publicClient,
  ...params
}: GetMintsOfContractParameters): Promise<{
  contract?: ContractInfo;
  tokens: MintableReturn[];
}> {
  const chainId = publicClient.chain.id;
  const mintGetterOrDefault: IOnchainMintGetter =
    mintGetter ?? new SubgraphMintGetter(chainId);
  const onchainMints = (
    await mintGetterOrDefault.getContractMintable({
      tokenAddress: params.tokenContract,
    })
  ).map((result) => toMintableReturn(result, chainId));

  const offchainMints = await getPremintsOfContractMintable({
    mintGetter: mintGetterOrDefault,
    premintGetter: premintGetter ?? new PremintAPIClient(chainId),
    publicClient,
    params: {
      tokenContract: params.tokenContract,
    },
  });

  const tokens = [...onchainMints, ...offchainMints];

  return {
    tokens: tokens,
    contract: tokens[0]?.token.contract,
  };
}

/**
 * Gets the costs to mint the quantity of tokens specified for a mint.
 * @param parameters - Parameters for the mint {@link GetMintCostsParameterArguments}
 * @returns Costs to mint the quantity of tokens specified
 */
export async function getMintCosts({
  params,
  allowListEntry,
  mintGetter,
  premintGetter,
  publicClient,
}: WithPublicClientAndRequiredGetters<{
  params: GetMintCostsParameterArguments;
  allowListEntry?: Pick<AllowListEntry, "price">;
}>) {
  const { quantityMinted: quantityToMint, collection } = params;
  if (isOnChainMint(params)) {
    const tokenId = is1155Mint(params) ? params.tokenId : undefined;
    const blockTime = (await publicClient.getBlock()).timestamp;
    const result = await mintGetter.getMintable({
      tokenId,
      tokenAddress: collection,
    });

    const token = parseAndFilterTokenQueryResult({
      token: result,
      tokenId,
      blockTime,
    });

    if (!token.salesConfigAndTokenInfo.salesConfig) {
      throw new Error("No valid sales config found for token");
    }

    return parseMintCosts({
      salesConfig: token.salesConfigAndTokenInfo.salesConfig,
      quantityToMint: BigInt(quantityToMint),
      allowListEntry,
    });
  }

  return getPremintMintCostsWithUnknownTokenPrice({
    premintGetter,
    publicClient: publicClient,
    quantityToMint: BigInt(quantityToMint),
    uid: params.uid,
    tokenContract: collection,
  });
}

async function getPremintsOfContractMintable({
  mintGetter,
  premintGetter,
  publicClient,
  params,
}: WithPublicClientAndRequiredGetters<{
  params: { tokenContract: Address };
}>): Promise<MintableReturn[]> {
  const { premints, collection } = await getPremintsOfCollectionWithTokenIds({
    mintGetter,
    premintGetter,
    tokenContract: params.tokenContract,
  });

  const offChainPremints = premints.filter(
    (premint) =>
      // if premint's uid is not in the list of uids from the subgraph, it is offchain
      typeof premint.tokenId === "undefined",
  );

  if (offChainPremints.length === 0) return [];

  const mintFee = await getPremintMintFee({
    publicClient,
    tokenContract: params.tokenContract,
  });

  return offChainPremints.map((premint) => {
    return toPremintMintReturn({
      premint: {
        premint: premint.premint,
        // todo: fix when api returns signer
        signer: zeroAddress,
        collection,
        collectionAddress: params.tokenContract,
        signature: premint.signature,
      },
      mintFee,
    });
  });
}

export function isPrimaryMintActive(
  premint: Pick<PremintFromApi, "premint">["premint"],
) {
  const currentTime = new Date().getTime() / 1000;

  return premint.premintConfig.tokenConfig.mintStart < currentTime;
}
/** Parsing */

function parsePremint({
  premint,
  mintFee,
}: {
  premint: Pick<
    PremintFromApi,
    "premint" | "signer" | "collectionAddress" | "collection"
  >;
  mintFee: bigint;
}): PremintSalesConfigAndTokenInfo {
  if (
    isPremintConfigV1(premint.premint) ||
    isPremintConfigV2(premint.premint)
  ) {
    return {
      creator: premint.signer,
      maxSupply: premint.premint.premintConfig.tokenConfig.maxSupply,
      mintType: "premint",
      uid: premint.premint.premintConfig.uid,
      contract: {
        address: premint.collectionAddress,
        name: premint.collection!.contractName,
        URI: premint.collection!.contractURI,
      },
      tokenURI: premint.premint.premintConfig.tokenConfig.tokenURI,
      totalMinted: 0n,
      salesConfig: {
        duration: premint.premint.premintConfig.tokenConfig.mintDuration,
        maxTokensPerAddress:
          premint.premint.premintConfig.tokenConfig.maxTokensPerAddress,
        pricePerToken: premint.premint.premintConfig.tokenConfig.pricePerToken,
        saleType: "premint",
        mintFeePerQuantity: mintFee,
      },
    };
  }

  throw new Error("Invalid premint config version");
}

export const makeOnchainPrepareMint =
  (result: OnchainSalesConfigAndTokenInfo, chainId: number): PrepareMint =>
  (params: MintParametersBase) => {
    if (!result.salesConfig) {
      throw new Error("No valid sales config found for token");
    }

    return {
      parameters: makeOnchainMintCall({
        token: result as Concrete<OnchainSalesConfigAndTokenInfo>,
        mintParams: params,
        chainId,
      }),
      erc20Approval: getRequiredErc20Approvals(params, result.salesConfig),
      costs: parseMintCosts({
        salesConfig: result.salesConfig,
        quantityToMint: BigInt(params.quantityToMint),
        allowListEntry: params.allowListEntry,
      }),
    };
  };

export function toMintableReturn(
  result: GetMintableReturn,
  chainId: number,
): MintableReturn {
  const primaryMintActive = result.primaryMintActive;
  if (!primaryMintActive) {
    return {
      token: result.salesConfigAndTokenInfo,
      primaryMintActive,
      primaryMintEnd: result.primaryMintEnd,
      secondaryMarketActive: result.secondaryMarketActive,
      prepareMint: undefined,
    };
  }
  return {
    token: result.salesConfigAndTokenInfo,
    primaryMintActive,
    primaryMintEnd: result.primaryMintEnd,
    secondaryMarketActive: result.secondaryMarketActive,
    prepareMint: makeOnchainPrepareMint(
      result.salesConfigAndTokenInfo,
      chainId,
    ),
  };
}

const makePremintPrepareMint = (
  mintable: PremintSalesConfigAndTokenInfo,
  mintFee: bigint,
  premint: Pick<
    PremintFromApi,
    "premint" | "signer" | "collectionAddress" | "collection" | "signature"
  >,
): PrepareMint => {
  return (params: MintParametersBase) => {
    return {
      parameters: buildPremintMintCall({
        mintArguments: params,
        mintFee,
        premint,
      }),
      costs: parseMintCosts({
        quantityToMint: BigInt(params.quantityToMint),
        salesConfig: mintable.salesConfig,
        allowListEntry: params.allowListEntry,
      }),
    };
  };
};

function toPremintMintReturn({
  premint,
  mintFee,
}: {
  premint: Pick<
    PremintFromApi,
    "premint" | "signer" | "collectionAddress" | "collection" | "signature"
  >;
  mintFee: bigint;
}): MintableReturn {
  const mintable = parsePremint({ premint, mintFee });

  const primaryMintActive = isPrimaryMintActive(premint.premint);

  if (!primaryMintActive) {
    return {
      token: mintable,
      primaryMintActive,
      prepareMint: undefined,
      secondaryMarketActive: false,
    };
  }
  return {
    token: mintable,
    primaryMintActive,
    secondaryMarketActive: false,
    prepareMint: makePremintPrepareMint(mintable, mintFee, premint),
  };
}

export function getRequiredErc20Approvals(
  params: MintParametersBase,
  salesConfig: OnchainSalesConfigAndTokenInfo["salesConfig"],
): Erc20Approval | undefined {
  if (salesConfig?.saleType !== "erc20") return undefined;

  return {
    quantity: salesConfig.pricePerToken * BigInt(params.quantityToMint),
    approveTo: salesConfig.address,
    erc20: salesConfig.currency,
  };
}
