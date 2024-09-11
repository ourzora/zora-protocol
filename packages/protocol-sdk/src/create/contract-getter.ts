import { ISubgraphQuerier } from "src/apis/subgraph-querier";
import { Address } from "viem";
import { buildContractInfoQuery } from "./subgraph-queries";
import { retriesGeneric } from "src/retries";
import { SubgraphGetter } from "src/apis/subgraph-getter";

export interface IContractGetter {
  getContractInfo: (params: {
    contractAddress: Address;
    retries?: number;
  }) => Promise<{
    name: string;
    contractVersion: string;
    nextTokenId: bigint;
    mintFee: bigint;
  }>;
}

export class SubgraphContractGetter
  extends SubgraphGetter
  implements IContractGetter
{
  constructor(chainId: number, subgraphQuerier?: ISubgraphQuerier) {
    super(chainId, subgraphQuerier);
  }

  async getContractInfo({
    contractAddress,
    retries = 1,
  }: {
    contractAddress: Address;
    retries?: number;
  }): Promise<{
    name: string;
    contractVersion: string;
    nextTokenId: bigint;
    mintFee: bigint;
  }> {
    const tryFn = async () => {
      const responseData = await this.querySubgraphWithRetries(
        buildContractInfoQuery({ contractAddress }),
      );
      if (!responseData) {
        console.log("could not find contract");
        throw new Error("Cannot find contract");
      }
      return responseData;
    };

    const responseData = await retriesGeneric({
      tryFn,
      maxTries: retries,
      linearBackoffMS: 1000,
    });

    const nextTokenId =
      responseData.tokens.length === 0
        ? 1n
        : BigInt(responseData.tokens[0]!.tokenId) + 1n;

    return {
      name: responseData.name,
      contractVersion: responseData.contractVersion,
      mintFee: BigInt(responseData.mintFeePerQuantity),
      nextTokenId,
    };
  }
}
