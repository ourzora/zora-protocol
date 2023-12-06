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
  PremintConfigForVersion,
  PremintConfigV1,
  PremintConfigV2,
  PremintConfigVersion,
  PremintConfigWithVersion,
} from "./contract-types";
import { Address, Hex } from "viem";

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

  return {
    ...result,
    // for now - we stub the backend api to simulate returning v1
    premint_config_version: PremintConfigVersion.V1,
  };
};

type OmitChainName<T> = Omit<T, "chain_name">;

const convertCollection = (
  collection: PremintSignatureGetResponse["collection"],
): ContractCreationConfig => ({
  ...collection,
  contractAdmin: collection.contractAdmin as Address,
});

/**
 * Convert server to on-chain types for a premint
 *
 * @param premint Premint object from the server to convert to one that's compatible with viem
 * @returns Viem type-compatible premint object
 */
const convertPremintV1 = (premint: PremintSignatureGetResponse["premint"]) => ({
  ...premint,
  tokenConfig: {
    ...premint.tokenConfig,
    fixedPriceMinter: premint.tokenConfig.fixedPriceMinter as Address,
    royaltyRecipient: premint.tokenConfig.royaltyRecipient as Address,
    maxSupply: BigInt(premint.tokenConfig.maxSupply),
    pricePerToken: BigInt(premint.tokenConfig.pricePerToken),
    mintStart: BigInt(premint.tokenConfig.mintStart),
    mintDuration: BigInt(premint.tokenConfig.mintDuration),
    maxTokensPerAddress: BigInt(premint.tokenConfig.maxTokensPerAddress),
  },
});

const encodePremintV1ForAPI = ({
  tokenConfig,
  ...premint
}: PremintConfigV1): PremintSignatureGetResponse["premint"] => ({
  ...premint,
  tokenConfig: {
    ...tokenConfig,
    maxSupply: tokenConfig.maxSupply.toString(),
    pricePerToken: tokenConfig.pricePerToken.toString(),
    mintStart: tokenConfig.mintStart.toString(),
    mintDuration: tokenConfig.mintDuration.toString(),
    maxTokensPerAddress: tokenConfig.maxTokensPerAddress.toString(),
  },
});

const encodePremintV2ForAPI = ({
  tokenConfig,
  ...premint
}: PremintConfigV2) => ({
  ...premint,
  tokenConfig: {
    ...tokenConfig,
    maxSupply: tokenConfig.maxSupply.toString(),
    pricePerToken: tokenConfig.pricePerToken.toString(),
    mintStart: tokenConfig.mintStart.toString(),
    mintDuration: tokenConfig.mintDuration.toString(),
    maxTokensPerAddress: tokenConfig.maxTokensPerAddress.toString(),
  },
});

const encodePremintForAPI = <T extends PremintConfigVersion>({
  premintConfig,
  premintConfigVersion,
}: PremintConfigWithVersion<T>) => {
  if (premintConfigVersion === PremintConfigVersion.V1) {
    return encodePremintV1ForAPI(premintConfig as PremintConfigV1);
  }
  if (premintConfigVersion === PremintConfigVersion.V2) {
    return encodePremintV2ForAPI(premintConfig as PremintConfigV2);
  }
  throw new Error(`Invalid premint config version ${premintConfigVersion}`);
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
    premintConfigVersion,
    premintConfig,
    signature,
  }: {
    collection: ContractCreationConfig;
    signature: Hex;
  } & PremintConfigWithVersion<T>): Promise<PremintSignatureResponse> => {
    if (premintConfigVersion === PremintConfigVersion.V1) {
      const data: OmitChainName<PremintSignatureRequestBody> = {
        premint: encodePremintForAPI<T>({
          premintConfig,
          premintConfigVersion,
        }) as PremintSignatureRequestBody["premint"],
        signature,
        collection,
      };
      return postSignature({
        ...data,
        chain_name: this.networkConfig.zoraBackendChainName,
        httpClient: this.httpClient,
      });
    } else {
      // TODO: support posting premint v2 sig when backend is ready
      throw new Error("Unsupported premint config version");
    }
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

    const premintConfigVersion =
      response.premint_config_version || PremintConfigVersion.V1;

    let premintConfig: PremintConfigForVersion<typeof premintConfigVersion>;

    if (premintConfigVersion === PremintConfigVersion.V1) {
      premintConfig = convertPremintV1(response.premint);
    } else {
      throw new Error(
        `Unsupported premint config version: ${premintConfigVersion}`,
      );
    }

    return {
      signature: response.signature as Hex,
      collection: convertCollection(response.collection),
      premintConfig,
      premintConfigVersion: premintConfigVersion,
    };
  };
}

export { ZORA_API_BASE, PremintAPIClient };
