import {
  IHttpClient,
  httpClient as defaultHttpClient,
} from "../apis/http-api-base";
import { components, paths } from "../apis/generated/premint-api-types";
import { ZORA_API_BASE } from "../constants";
import { NetworkConfig } from "src/apis/chain-constants";
import { getApiNetworkConfigForChain } from "src/mint/mint-api-client";

type SignaturePostType = paths["/signature"]["post"];
type PremintSignatureRequestBody =
  SignaturePostType["requestBody"]["content"]["application/json"];
export type PremintSignatureResponse =
  SignaturePostType["responses"][200]["content"]["application/json"];

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
}): Promise<PremintSignatureGetResponse> =>
  retries(() =>
    get<PremintSignatureGetResponse>(
      `${ZORA_API_BASE}premint/signature/${chain_name}/${collection_address}/${uid}`,
    ),
  );

type OmitChainName<T> = Omit<T, "chain_name">;

class PremintAPIClient {
  httpClient: IHttpClient;
  networkConfig: NetworkConfig;

  constructor(chainId: number, httpClient?: IHttpClient) {
    this.httpClient = httpClient || defaultHttpClient;
    this.networkConfig = getApiNetworkConfigForChain(chainId);
  }
  postSignature = async (
    data: OmitChainName<PremintSignatureRequestBody>,
  ): Promise<PremintSignatureResponse> =>
    postSignature({
      ...data,
      chain_name: this.networkConfig.zoraBackendChainName,
      httpClient: this.httpClient,
    });

  getNextUID = async (
    path: OmitChainName<PremintNextUIDGetPathParameters>,
  ): Promise<PremintNextUIDGetResponse> =>
    getNextUID({
      ...path,
      chain_name: this.networkConfig.zoraBackendChainName,
      httpClient: this.httpClient,
    });

  getSignature = async ({
    collection_address,
    uid,
  }: OmitChainName<PremintSignatureGetPathParameters>): Promise<PremintSignatureGetResponse> =>
    getSignature({
      collection_address,
      uid,
      chain_name: this.networkConfig.zoraBackendChainName,
      httpClient: this.httpClient,
    });
}

export { ZORA_API_BASE, PremintAPIClient };
