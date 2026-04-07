import { getCoinComments } from "@zoralabs/coins-sdk";
import { Address } from "viem";

export async function fetchCoinComments() {
  const response = await getCoinComments({
    address: "0xCoinContractAddress" as Address,
    chain: 8453, // Optional: Base chain
    after: undefined, // Optional: for pagination
    count: 20, // Optional: number of comments per page
  });

  // Process comments
  console.log(
    `Found ${response.data?.zora20Token?.zoraComments?.edges?.length || 0} comments`,
  );

  response.data?.zora20Token?.zoraComments?.edges?.forEach(
    (edge, index: number) => {
      console.log(`Comment ${index + 1}:`);
      console.log(
        `- Author: ${edge.node?.userProfile?.handle || edge.node?.userAddress}`,
      );
      console.log(`- Text: ${edge.node?.comment}`);
      console.log(`- Created At: ${edge.node?.timestamp}`);

      edge.node?.replies?.edges?.forEach((reply: any) => {
        console.log(`- Reply: ${reply.node.text}`);
      });

      console.log("-----------------------------------");
    },
  );

  // For pagination
  if (response.data?.zora20Token?.zoraComments?.pageInfo?.endCursor) {
    console.log(
      "Next page cursor:",
      response.data?.zora20Token?.zoraComments?.pageInfo?.endCursor,
    );
  }

  return response;
}
