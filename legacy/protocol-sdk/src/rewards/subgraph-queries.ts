import { ISubgraphQuery } from "src/apis/subgraph-querier";
import { Address } from "viem";

export type RewardsToken = {
  salesStrategies: [
    {
      zoraTimedMinter?: {
        erc20Z: {
          id: Address;
        };
      };
    },
  ];
};

export type CreatorERC20zQueryResult = {
  zoraCreateTokens: RewardsToken[];
};

export function buildCreatorERC20zs({
  address,
}: {
  address: Address;
}): ISubgraphQuery<CreatorERC20zQueryResult["zoraCreateTokens"]> {
  return {
    query: `
    query ($address: Bytes!) {
      zoraCreateTokens(
        where: { royalties_: { royaltyRecipient: $address }, salesStrategies_: { type: "ZORA_TIMED" } }
      ) {
        royalties {
          user
        }
        salesStrategies {
          zoraTimedMinter {
            erc20Z {
              id
            }
          }
        }
      }
    }
    `,
    variables: { address },
    parseResponseData: (responseData: any | undefined) => {
      return responseData?.zoraCreateTokens;
    },
  };
}
