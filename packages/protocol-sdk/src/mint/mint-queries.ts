import { IPremintGetter } from "src/premint/premint-api-client";
import {
  ContractInfo,
  Erc20Approval,
  GetMintCostsParameters,
  GetMintParameters,
  GetMintsOfContractParameters,
  IOnchainMintGetter,
  MintParametersBase,
  MintableReturn,
  OnchainSalesConfigAndTokenInfo,
  PremintSalesConfigAndTokenInfo,
  PrepareMint,
  is1155Mint,
  isOnChainMint,
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
import { IPublicClient } from "src/types";

export async function getMint({
  params,
  mintGetter,
  premintGetter,
  publicClient,
}: {
  params: GetMintParameters;
  mintGetter: IOnchainMintGetter;
  premintGetter: IPremintGetter;
  publicClient: IPublicClient;
}): Promise<MintableReturn> {
  const { tokenContract } = params;
  if (isOnChainMint(params)) {
    const tokenId = is1155Mint(params) ? params.tokenId : undefined;
    const result = await mintGetter.getMintable({
      tokenId,
      tokenAddress: tokenContract,
      preferredSaleType: params.preferredSaleType,
    });

    return toMintableReturn(result);
  }

  const premint = await premintGetter.get({
    collectionAddress: tokenContract,
    uid: params.uid,
  });

  const mintFee = await getPremintMintFee({
    publicClient,
    tokenContract: tokenContract,
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

export async function getMintsOfContract({
  params,
  mintGetter,
  premintGetter,
  publicClient,
}: {
  params: GetMintsOfContractParameters;
  mintGetter: IOnchainMintGetter;
  premintGetter: IPremintGetter;
  publicClient: IPublicClient;
}): Promise<{ contract?: ContractInfo; tokens: MintableReturn[] }> {
  const onchainMints = (
    await mintGetter.getContractMintable({
      tokenAddress: params.tokenContract,
    })
  ).map(toMintableReturn);

  const offchainMints = await getPremintsOfContractMintable({
    mintGetter,
    premintGetter,
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

export async function getMintCosts({
  params,
  mintGetter,
  premintGetter,
  publicClient,
}: {
  params: GetMintCostsParameters;
  mintGetter: IOnchainMintGetter;
  premintGetter: IPremintGetter;
  publicClient: IPublicClient;
}) {
  const { quantityMinted: quantityToMint, collection } = params;
  if (isOnChainMint(params)) {
    const tokenId = is1155Mint(params) ? params.tokenId : undefined;
    const salesConfigAndTokenInfo = await mintGetter.getMintable({
      tokenId,
      tokenAddress: collection,
    });

    return parseMintCosts({
      mintFeePerQuantity: salesConfigAndTokenInfo.mintFeePerQuantity,
      salesConfig: salesConfigAndTokenInfo.salesConfig,
      quantityToMint: BigInt(quantityToMint),
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
}: {
  mintGetter: IOnchainMintGetter;
  premintGetter: IPremintGetter;
  publicClient: IPublicClient;
  params: { tokenContract: Address };
}): Promise<MintableReturn[]> {
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
      mintFeePerQuantity: mintFee,
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
      },
    };
  }

  throw new Error("Invalid premint config version");
}

const makeOnchainPrepareMint =
  (result: OnchainSalesConfigAndTokenInfo): PrepareMint =>
  (params: MintParametersBase) => ({
    parameters: makeOnchainMintCall({ token: result, mintParams: params }),
    erc20Approval: getRequiredErc20Approvals(params, result),
    costs: parseMintCosts({
      salesConfig: result.salesConfig,
      quantityToMint: BigInt(params.quantityToMint),
      mintFeePerQuantity: result.mintFeePerQuantity,
    }),
  });

function toMintableReturn(
  result: OnchainSalesConfigAndTokenInfo,
): MintableReturn {
  return { token: result, prepareMint: makeOnchainPrepareMint(result) };
}

const makePremintPrepareMint =
  (
    mintable: PremintSalesConfigAndTokenInfo,
    mintFee: bigint,
    premint: Pick<
      PremintFromApi,
      "premint" | "signer" | "collectionAddress" | "collection" | "signature"
    >,
  ): PrepareMint =>
  (params: MintParametersBase) => ({
    parameters: buildPremintMintCall({
      mintArguments: params,
      mintFee,
      premint,
    }),
    costs: parseMintCosts({
      mintFeePerQuantity: mintFee,
      quantityToMint: BigInt(params.quantityToMint),
      salesConfig: mintable.salesConfig,
    }),
  });

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

  return {
    token: mintable,
    prepareMint: makePremintPrepareMint(mintable, mintFee, premint),
  };
}
function getRequiredErc20Approvals(
  params: MintParametersBase,
  result: OnchainSalesConfigAndTokenInfo,
): Erc20Approval | undefined {
  if (result.salesConfig.saleType !== "erc20") return undefined;

  return {
    quantity: result.salesConfig.pricePerToken * BigInt(params.quantityToMint),
    approveTo: result.salesConfig.address,
    erc20: result.salesConfig.currency,
  };
}
