import { getCoinComments, GetCoinCommentsResponse } from "@zoralabs/coins-sdk";

export async function fetchAllCoinComments(coinAddress: string) {
  let allComments: NonNullable<
    NonNullable<
      NonNullable<GetCoinCommentsResponse["zora20Token"]>["zoraComments"]
    >["edges"]
  > = [];
  let cursor = undefined;
  const pageSize = 20;

  // Continue fetching until no more pages
  do {
    const response = await getCoinComments({
      address: coinAddress,
      count: pageSize,
      after: cursor,
    });

    // Add comments to our collection
    if (
      response.data?.zora20Token?.zoraComments?.edges &&
      response.data?.zora20Token?.zoraComments?.edges.length > 0
    ) {
      allComments = [
        ...allComments,
        ...response.data?.zora20Token?.zoraComments?.edges,
      ];
    }

    // Update cursor for next page
    cursor = response.data?.zora20Token?.zoraComments?.pageInfo?.endCursor;

    // Break if no more results
    if (
      !cursor ||
      response.data?.zora20Token?.zoraComments?.edges?.length === 0
    ) {
      break;
    }
  } while (true);

  console.log(`Fetched ${allComments.length} total comments`);
  return allComments;
}
