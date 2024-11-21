import { Address } from "viem";
import { IPublicClient } from "src/types";
import {
  GetMintParameters,
  IOnchainMintGetter,
  MintCosts,
  PrepareMintReturn,
  SaleType,
} from "./types";
import { MakeMintParametersArguments, GetMintCostsParameters } from "./types";
import { IPremintGetter } from "src/premint/premint-api-client";

import { getMint, getMintCosts, getMintsOfContract } from "./mint-queries";

class MintError extends Error {}
class MintInactiveError extends Error {}

export const Errors = {
  MintError,
  MintInactiveError,
};

export class MintClient {
  private readonly publicClient: IPublicClient;
  private readonly mintGetter: IOnchainMintGetter;
  private readonly premintGetter: IPremintGetter;
  private readonly chainId: number;
  constructor({
    publicClient,
    premintGetter,
    mintGetter,
    chainId,
  }: {
    publicClient: IPublicClient;
    premintGetter: IPremintGetter;
    mintGetter: IOnchainMintGetter;
    chainId: number;
  }) {
    this.publicClient = publicClient;
    this.mintGetter = mintGetter;
    this.premintGetter = premintGetter;
    this.chainId = chainId;
  }

  /**
   * Returns the parameters needed to prepare a transaction mint a token.
   * Works with premint, onchain 1155, and onchain 721.
   *
   * @param parameters - Parameters for collecting the token {@link MakeMintParametersArguments}
   * @returns Parameters for simulating/executing the mint transaction, any necessary erc20 approval, and costs to mint
   */
  async mint(
    parameters: MakeMintParametersArguments,
  ): Promise<PrepareMintReturn> {
    return mint({
      parameters,
      publicClient: this.publicClient,
      mintGetter: this.mintGetter,
      premintGetter: this.premintGetter,
      chainId: this.chainId,
    });
  }

  /**
   * Gets an 1155, 721, or premint, and returns both information about it, and a function
   * that can be used to build a mint transaction for a quantity of items to mint.
   * @param parameters - Token to get {@link GetMintParameters}
   * @Returns Information about the mint and a function to build a mint transaction {@link MintableReturn}
   */
  async get(parameters: GetMintParameters) {
    return getMint({
      params: parameters,
      mintGetter: this.mintGetter,
      premintGetter: this.premintGetter,
      publicClient: this.publicClient,
      chainId: this.chainId,
    });
  }

  /**
   * Gets onchain and premint tokens of an 1155 contract.  For each token returns both information about it, and a function
   * that can be used to build a mint transaction for a quantity of items to mint.
   * @param parameters - Contract address to get tokens for {@link GetMintsOfContractParameters}
   * @Returns Array of tokens, each containing information about the token and a function to build a mint transaction.
   */
  async getOfContract(params: {
    tokenContract: Address;
    preferredSaleType?: SaleType;
  }) {
    return getMintsOfContract({
      params,
      mintGetter: this.mintGetter,
      premintGetter: this.premintGetter,
      publicClient: this.publicClient,
      chainId: this.chainId,
    });
  }

  /**
   * Gets the costs to mint the quantity of tokens specified for a mint.
   * @param parameters - Parameters for the mint {@link GetMintCostsParameters}
   * @returns Costs to mint the quantity of tokens specified
   */
  async getMintCosts(parameters: GetMintCostsParameters): Promise<MintCosts> {
    return getMintCosts({
      params: parameters,
      mintGetter: this.mintGetter,
      premintGetter: this.premintGetter,
      publicClient: this.publicClient,
    });
  }
}

async function mint({
  parameters,
  publicClient,
  mintGetter,
  premintGetter,
  chainId,
}: {
  parameters: MakeMintParametersArguments;
  publicClient: IPublicClient;
  mintGetter: IOnchainMintGetter;
  premintGetter: IPremintGetter;
  chainId: number;
}): Promise<PrepareMintReturn> {
  const { prepareMint, primaryMintActive } = await getMint({
    params: parameters,
    mintGetter,
    premintGetter,
    publicClient,
    chainId,
  });

  if (!primaryMintActive) {
    throw new Error("Primary mint is not active");
  }

  return prepareMint!({
    minterAccount: parameters.minterAccount,
    quantityToMint: parameters.quantityToMint,
    firstMinter: parameters.firstMinter,
    mintComment: parameters.mintComment,
    mintRecipient: parameters.mintRecipient,
    mintReferral: parameters.mintReferral,
  });
}
