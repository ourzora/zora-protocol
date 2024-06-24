import { networkConfigByChain } from "src/apis/chain-constants";
import { components, paths } from "src/apis/generated/premint-api-types";
import { Address, Hex } from "viem";
import {
  ContractCreationConfig,
  PremintConfigAndVersion,
  PremintConfigV1,
  PremintConfigV2,
  PremintConfigVersion,
  PremintConfigWithVersion,
} from "@zoralabs/protocol-deployments";
import {
  PremintSignatureGetOfCollectionResponse,
  PremintSignatureGetResponse,
} from "./premint-api-client";
import { ContractCreationConfigOrAddress } from "./contract-types";

export const convertCollectionFromApi = (
  collection: PremintSignatureGetResponse["collection"],
): ContractCreationConfig | undefined => {
  if (!collection) return undefined;

  return {
    additionalAdmins:
      (collection.additionalAdmins as Address[] | undefined) || [],
    contractAdmin: collection.contractAdmin as Address,
    contractName: collection.contractName,
    contractURI: collection.contractURI,
  };
};

/**
 * Convert server to on-chain types for a premint
 *
 * @param premint Premint object from the server to convert to one that's compatible with viem
 * @returns Viem type-compatible premint object
 */
export const convertPremintFromApi = (
  premint: PremintSignatureGetResponse["premint"],
): PremintConfigAndVersion => {
  if (
    premint.config_version === PremintConfigVersion.V1 ||
    !premint.config_version
  ) {
    const tokenConfig =
      premint.tokenConfig as components["schemas"]["TokenCreationConfigV1"];
    return {
      premintConfigVersion: PremintConfigVersion.V1,
      premintConfig: {
        deleted: premint.deleted,
        uid: premint.uid,
        version: premint.version,
        tokenConfig: {
          ...tokenConfig,
          fixedPriceMinter: tokenConfig.fixedPriceMinter as Address,
          royaltyRecipient: tokenConfig.royaltyRecipient as Address,
          maxSupply: BigInt(tokenConfig.maxSupply),
          pricePerToken: BigInt(tokenConfig.pricePerToken),
          mintStart: BigInt(tokenConfig.mintStart),
          mintDuration: BigInt(tokenConfig.mintDuration),
          maxTokensPerAddress: BigInt(tokenConfig.maxTokensPerAddress),
        },
      },
    };
  } else {
    const tokenConfig =
      premint.tokenConfig as components["schemas"]["TokenCreationConfigV2"];
    return {
      premintConfigVersion: PremintConfigVersion.V2,
      premintConfig: {
        deleted: premint.deleted,
        uid: premint.uid,
        version: premint.version,
        tokenConfig: {
          ...tokenConfig,
          fixedPriceMinter: tokenConfig.fixedPriceMinter as Address,
          payoutRecipient: tokenConfig.payoutRecipient as Address,
          createReferral: tokenConfig.createReferral as Address,
          maxSupply: BigInt(tokenConfig.maxSupply),
          pricePerToken: BigInt(tokenConfig.pricePerToken),
          mintStart: BigInt(tokenConfig.mintStart),
          mintDuration: BigInt(tokenConfig.mintDuration),
          maxTokensPerAddress: BigInt(tokenConfig.maxTokensPerAddress),
        },
      },
    };
  }
};

export type PremintFromApi = ReturnType<typeof convertGetPremintApiResponse>;

export const convertGetPremintApiResponse = (
  response: PremintSignatureGetResponse,
) => ({
  collection: convertCollectionFromApi(response.collection),
  collectionAddress: response.collection_address as Address,
  signature: response.signature as Hex,
  signer: response.signer as Address,
  premint: convertPremintFromApi(response.premint),
});

export type PremintCollectionFromApi = ReturnType<
  typeof convertGetPremintOfCollectionApiResponse
>;

export const convertGetPremintOfCollectionApiResponse = (
  response: PremintSignatureGetOfCollectionResponse,
) => ({
  collection: convertCollectionFromApi({
    contractAdmin: response.contract_admin,
    contractName: response.contract_name,
    contractURI: response.contract_uri,
  }),
  premints: response.premints.map((premint) => ({
    premint: convertPremintFromApi(premint),
    signature: premint.signature as Hex,
  })),
});

const encodePremintV1ForAPI = ({
  tokenConfig,
  ...premint
}: PremintConfigV1): PremintSignatureGetResponse["premint"] => ({
  ...premint,
  config_version: "1",
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
}: PremintConfigV2): PremintSignatureRequestBody["premint"] => ({
  ...premint,
  config_version: "2",
  tokenConfig: {
    ...tokenConfig,
    maxSupply: tokenConfig.maxSupply.toString(),
    pricePerToken: tokenConfig.pricePerToken.toString(),
    mintStart: tokenConfig.mintStart.toString(),
    mintDuration: tokenConfig.mintDuration.toString(),
    maxTokensPerAddress: tokenConfig.maxTokensPerAddress.toString(),
  },
});

export const encodePremintForAPI = <T extends PremintConfigVersion>({
  premintConfig,
  premintConfigVersion,
}: PremintConfigWithVersion<T>): PremintSignatureRequestBody["premint"] => {
  if (premintConfigVersion === PremintConfigVersion.V1) {
    return encodePremintV1ForAPI(premintConfig as PremintConfigV1);
  }
  if (premintConfigVersion === PremintConfigVersion.V2) {
    return encodePremintV2ForAPI(premintConfig as PremintConfigV2);
  }
  throw new Error(`Invalid premint config version ${premintConfigVersion}`);
};

export type SignaturePostType = paths["/signature"]["post"];
export type PremintSignatureRequestBody =
  SignaturePostType["requestBody"]["content"]["application/json"];
export type PremintSignatureResponse =
  SignaturePostType["responses"][200]["content"]["application/json"];

/**
 * Encode input for posting a premint signature to the premint api
 * @param param0
 * @returns
 */
export const encodePostSignatureInput = <T extends PremintConfigVersion>({
  contract: collection,
  contractAddress: collectionAddress,
  premintConfigVersion,
  premintConfig,
  signature,
  chainId,
}: {
  signature: Hex;
  chainId: number;
} & PremintConfigWithVersion<T> &
  ContractCreationConfigOrAddress): PremintSignatureRequestBody => ({
  premint: encodePremintForAPI({
    premintConfig,
    premintConfigVersion,
  }),
  signature,
  collection: collection as
    | PremintSignatureRequestBody["collection"]
    | undefined,
  collection_address: collectionAddress,
  chain_name: networkConfigByChain[chainId]!.zoraBackendChainName,
});

export const isPremintConfigV1 = (
  premintConfigAndVersion: PremintConfigAndVersion,
): premintConfigAndVersion is PremintConfigWithVersion<PremintConfigVersion.V1> =>
  premintConfigAndVersion.premintConfigVersion === PremintConfigVersion.V1;

export const isPremintConfigV2 = (
  premintConfigAndVersion: PremintConfigAndVersion,
): premintConfigAndVersion is PremintConfigWithVersion<PremintConfigVersion.V2> =>
  premintConfigAndVersion.premintConfigVersion === PremintConfigVersion.V2;
