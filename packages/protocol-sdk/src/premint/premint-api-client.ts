import {
  IHttpClient,
  httpClient as defaultHttpClient,
} from "../apis/http-api-base";
import { components, paths } from "../apis/generated/premint-api-types";
import { ZORA_API_BASE } from "../constants";
import { NetworkConfig } from "src/apis/chain-constants";
import { getApiNetworkConfigForChain } from "src/mint/mint-api-client";
import {
  ContractCreationConfig,
  PremintConfigAndVersion,
  PremintConfigVersion,
  PremintConfigWithVersion,
} from "@zoralabs/protocol-deployments";
import { Address, Hex } from "viem";
import {
  PremintSignatureRequestBody,
  PremintSignatureResponse,
  convertGetPremintApiResponse,
  encodePostSignatureInput,
} from "./conversions";

type PremintNextUIDGetType =
  paths["/signature/{chain_name}/{collection_address}/next_uid"]["get"];
type PremintNextUIDGetPathParameters =
  PremintNextUIDGetType["parameters"]["path"];
export type PremintNextUIDGetResponse =
  PremintNextUIDGetType["responses"][200]["content"]["application/json"];

type SignaturePremintGetType =
  paths["/signature/{chain_name}/{collection_address}/{uid}"]["get"];
type PremintSignatureGetPathParameters =
  SignaturePremintGetType["parameters"]["path"];
export type PremintSignatureGetResponse =
  SignaturePremintGetType["responses"][200]["content"]["application/json"];

export type PremintCollection = PremintSignatureGetResponse["collection"];

export type BackendChainNames = components["schemas"]["ChainName"];

const postSignature = async ({
  httpClient: { post, retries } = defaultHttpClient,
  ...data
}: PremintSignatureRequestBody & {
  httpClient?: Pick<IHttpClient, "retries" | "post">;
}): Promise<PremintSignatureResponse> =>
  retries(() =>
    post<PremintSignatureResponse>(`${ZORA_API_BASE}premint/signature`, data),
  );

const getNextUID = async ({
  chain_name,
  collection_address,
  httpClient: { retries, get } = defaultHttpClient,
}: PremintNextUIDGetPathParameters & {
  httpClient?: Pick<IHttpClient, "retries" | "get">;
}): Promise<PremintNextUIDGetResponse> =>
  retries(() =>
    get<PremintNextUIDGetResponse>(
      `${ZORA_API_BASE}premint/signature/${chain_name}/${collection_address}/next_uid`,
    ),
  );

const getSignature = async ({
  collection_address,
  uid,
  chain_name,
  httpClient: { retries, get } = defaultHttpClient,
}: PremintSignatureGetPathParameters & {
  httpClient?: Pick<IHttpClient, "retries" | "get">;
}): Promise<
  PremintSignatureGetResponse & {
    premint_config_version?: PremintConfigVersion;
  }
> => {
  const result = await retries(() =>
    get<PremintSignatureGetResponse>(
      `${ZORA_API_BASE}premint/signature/${chain_name}/${collection_address}/${uid}`,
    ),
  );

  return result;
};

class PremintAPIClient {
  httpClient: IHttpClient;
  networkConfig: NetworkConfig;

  constructor(chainId: number, httpClient?: IHttpClient) {
    this.httpClient = httpClient || defaultHttpClient;
    this.networkConfig = getApiNetworkConfigForChain(chainId);
  }
  postSignature = async <T extends PremintConfigVersion>({
    collection,
    signature,
    ...premintConfigAndVersion
  }: {
    collection: ContractCreationConfig;
    signature: Hex;
  } & PremintConfigWithVersion<T>): Promise<PremintSignatureResponse> => {
    const data = encodePostSignatureInput({
      collection,
      ...premintConfigAndVersion,
      chainId: this.networkConfig.chainId,
      signature,
    });
    return postSignature({
      ...data,
      httpClient: this.httpClient,
    });
  };

  getNextUID = async (collectionAddress: Address): Promise<number> =>
    (
      await getNextUID({
        collection_address: collectionAddress.toLowerCase(),
        chain_name: this.networkConfig.zoraBackendChainName,
        httpClient: this.httpClient,
      })
    ).next_uid;

  getSignature = async ({
    collectionAddress,
    uid,
  }: {
    collectionAddress: Address;
    uid: number;
  }): Promise<
    {
      signature: Hex;
      collection: ContractCreationConfig;
    } & PremintConfigAndVersion
  > => {
    const response = await getSignature({
      collection_address: collectionAddress.toLowerCase(),
      uid,
      chain_name: this.networkConfig.zoraBackendChainName,
      httpClient: this.httpClient,
    });

    return convertGetPremintApiResponse(response);
  };
}

export { ZORA_API_BASE, PremintAPIClient };
