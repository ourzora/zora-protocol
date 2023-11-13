import { retries, get, post } from "../apis/http-api-base";
import { paths } from "../apis/generated/discover-api-types";
import { ZORA_API_BASE } from "../constants";

export type MintableGetToken =
  paths["/mintables/{chain_name}/{collection_address}"];
type MintableGetTokenPathParameters =
  MintableGetToken["get"]["parameters"]["path"];
type MintableGetTokenGetQueryParameters =
  MintableGetToken["get"]["parameters"]["query"];
export type MintableGetTokenResponse =
  MintableGetToken["get"]["responses"][200]["content"]["application/json"];

function encodeQueryParameters(params: Record<string, string>) {
  return new URLSearchParams(params).toString();
}

const getMintable = async (
  path: MintableGetTokenPathParameters,
  query: MintableGetTokenGetQueryParameters,
): Promise<MintableGetTokenResponse> =>
  retries(() => {
    return get<MintableGetTokenResponse>(
      `${ZORA_API_BASE}discover/mintables/${path.chain_name}/${
        path.collection_address
      }${query?.token_id ? `?${encodeQueryParameters(query)}` : ""}`,
    );
  });

export const getSalesConfigFixedPrice = async ({
  contractAddress,
  tokenId,
  subgraphUrl,
}: {
  contractAddress: string;
  tokenId: string;
  subgraphUrl: string;
}): Promise<undefined | string> =>
  retries(async () => {
    const response = await post<any>(subgraphUrl, {
      query:
        "query($id: ID!) {\n  zoraCreateToken(id: $id) {\n    id\n    salesStrategies{\n      fixedPrice {\n        address\n      }\n    }\n  }\n}",
      variables: { id: `${contractAddress.toLowerCase()}-${tokenId}` },
    });
    return response.zoraCreateToken?.salesStrategies?.find(() => true)
      ?.fixedPriceMinterAddress;
  });

export const MintAPIClient = {
  getMintable,
  getSalesConfigFixedPrice,
};
