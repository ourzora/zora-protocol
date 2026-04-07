import { ISubgraphQuery } from "src/apis/subgraph-querier";
import { Address } from "viem";

export function buildContractInfoQuery({
  contractAddress,
}: {
  contractAddress: Address;
}): ISubgraphQuery<{
  name: string;
  contractVersion: string;
  mintFeePerQuantity: string;
  tokens: {
    tokenId: Address;
  }[];
}> {
  return {
    query: `
    query ($contractAddress: Bytes!) {
      zoraCreateContract(id: $contractAddress) {
        contractVersion
        name
        mintFeePerQuantity
        tokens(first: 1, orderBy: tokenId, orderDirection: desc) {
          tokenId
        }
      }
    }
    `,
    variables: {
      contractAddress: contractAddress.toLowerCase(),
    },
    parseResponseData: (responseData: any | undefined) =>
      responseData.zoraCreateContract,
  };
}
