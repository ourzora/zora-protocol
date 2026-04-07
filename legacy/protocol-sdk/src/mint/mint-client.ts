import { Address } from "viem";
import { IPublicClient } from "src/types";
import {
  GetMintParametersArguments,
  IOnchainMintGetter,
  MakeMintParameters,
  MintCosts,
  PrepareMintReturn,
  SaleType,
} from "./types";
import {
  MakeMintParametersArguments,
  GetMintCostsParameterArguments,
} from "./types";
import { IPremintGetter } from "src/premint/premint-api-client";

import { getToken, getMintCosts, getTokensOfContract } from "./mint-queries";

class MintError extends Error {}
class MintInactiveError extends Error {}

export const Errors = {
  MintError,
  MintInactiveError,
};

/**
 * @deprecated Please use functions directly without creating a client.
 * Example: Instead of `new MintClient().mint()`, use `mint()`
 * Import the functions you need directly from their respective modules:
 * import { mint, getToken, getTokensOfContract, getMintCosts } from '@zoralabs/protocol-sdk'
 */
export class MintClient {
  private readonly publicClient: IPublicClient;
  private readonly mintGetter: IOnchainMintGetter;
  private readonly premintGetter: IPremintGetter;
  constructor({
    publicClient,
    premintGetter,
    mintGetter,
  }: {
    publicClient: IPublicClient;
    premintGetter: IPremintGetter;
    mintGetter: IOnchainMintGetter;
  }) {
    this.publicClient = publicClient;
    this.mintGetter = mintGetter;
    this.premintGetter = premintGetter;
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
      ...parameters,
      publicClient: this.publicClient,
      mintGetter: this.mintGetter,
      premintGetter: this.premintGetter,
    });
  }

  /**
   * Gets an 1155, 721, or premint, and returns both information about it, and a function
   * that can be used to build a mint transaction for a quantity of items to mint.
   * @param parameters - Token to get {@link GetMintParametersArguments}
   * @Returns Information about the mint and a function to build a mint transaction {@link MintableReturn}
   */
  async get(parameters: GetMintParametersArguments) {
    return getToken({
      ...parameters,
      mintGetter: this.mintGetter,
      premintGetter: this.premintGetter,
      publicClient: this.publicClient,
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
    return getTokensOfContract({
      ...params,
      mintGetter: this.mintGetter,
      premintGetter: this.premintGetter,
      publicClient: this.publicClient,
    });
  }

  /**
   * Gets the costs to mint the quantity of tokens specified for a mint.
   * @param parameters - Parameters for the mint {@link GetMintCostsParameterArguments}
   * @returns Costs to mint the quantity of tokens specified
   */
  async getMintCosts(
    parameters: GetMintCostsParameterArguments,
  ): Promise<MintCosts> {
    return getMintCosts({
      params: parameters,
      mintGetter: this.mintGetter,
      premintGetter: this.premintGetter,
      publicClient: this.publicClient,
    });
  }
}

/**
 * Returns the parameters needed to prepare a transaction mint a token.
 * Works with premint, onchain 1155, and onchain 721.
 *
 * @param parameters - Parameters for collecting the token {@link MakeMintParameters}
 * @returns Parameters for simulating/executing the mint transaction, any necessary erc20 approval, and costs to mint
 */
export async function mint({
  publicClient,
  mintGetter,
  premintGetter,
  ...parameters
}: MakeMintParameters): Promise<PrepareMintReturn> {
  const { prepareMint, primaryMintActive } = await getToken({
    ...parameters,
    mintGetter,
    premintGetter,
    publicClient,
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
