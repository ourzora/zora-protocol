import { post, retries, get } from "../apis/http-api-base";
import { components, paths } from "../apis/generated/premint-api-types";
import { ZORA_API_BASE } from "../constants";

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

export type BackendChainNames = components["schemas"]["ChainName"];

const postSignature = async (
  data: PremintSignatureRequestBody,
): Promise<PremintSignatureResponse> =>
  retries(() =>
    post<PremintSignatureResponse>(`${ZORA_API_BASE}premint/signature`, data),
  );

const getNextUID = async (
  path: PremintNextUIDGetPathParameters,
): Promise<PremintNextUIDGetResponse> =>
  retries(() =>
    get<PremintNextUIDGetResponse>(
      `${ZORA_API_BASE}premint/signature/${path.chain_name}/${path.collection_address}/next_uid`,
    ),
  );

const getSignature = async (
  path: PremintSignatureGetPathParameters,
): Promise<PremintSignatureGetResponse> =>
  retries(() =>
    get<PremintSignatureGetResponse>(
      `${ZORA_API_BASE}premint/signature/${path.chain_name}/${path.collection_address}/${path.uid}`,
    ),
  );

export const PremintAPIClient = {
  postSignature,
  getSignature,
  getNextUID,
};
export { ZORA_API_BASE };
