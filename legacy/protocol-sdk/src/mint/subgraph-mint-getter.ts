import { Address } from "viem";
import { ISubgraphQuerier } from "../apis/subgraph-querier";
import { IOnchainMintGetter, SaleType } from "./types";
import {
  buildContractTokensQuery,
  buildNftTokenSalesQuery,
  buildPremintsOfContractQuery,
} from "./subgraph-queries";
import { SubgraphGetter } from "src/apis/subgraph-getter";
import { parseAndFilterTokenQueryResult } from "./strategies-parsing";

export class SubgraphMintGetter
  extends SubgraphGetter
  implements IOnchainMintGetter
{
  constructor(chainId: number, subgraphQuerier?: ISubgraphQuerier) {
    super(chainId, subgraphQuerier);
  }

  getMintable: IOnchainMintGetter["getMintable"] = async ({
    tokenAddress,
    tokenId,
  }) => {
    const token = await this.querySubgraphWithRetries(
      buildNftTokenSalesQuery({
        tokenId,
        tokenAddress,
      }),
    );

    if (!token) {
      throw new Error("Cannot find token");
    }

    return token;
  };

  async getContractMintable({
    tokenAddress,
    preferredSaleType,
    blockTime,
  }: {
    tokenAddress: Address;
    preferredSaleType?: SaleType;
    blockTime: bigint;
  }) {
    const tokens = await this.querySubgraphWithRetries(
      buildContractTokensQuery({
        tokenAddress,
      }),
    );

    if (!tokens || tokens.length === 0) return [];

    return tokens
      .filter((x) => x.tokenId !== "0")
      .map((token) =>
        parseAndFilterTokenQueryResult({
          token,
          tokenId: token.tokenId,
          preferredSaleType,
          blockTime,
        }),
      );
  }

  async getContractPremintTokenIds({
    tokenAddress,
  }: {
    tokenAddress: Address;
  }) {
    const premints = await this.querySubgraphWithRetries(
      buildPremintsOfContractQuery({
        tokenAddress,
      }),
    );

    return (
      premints?.map((premint) => ({
        tokenId: BigInt(premint.tokenId),
        uid: +premint.uid,
      })) || []
    );
  }
}
