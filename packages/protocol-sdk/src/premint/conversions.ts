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
} from "./contract-types";
import { PremintSignatureGetResponse } from "./premint-api-client";

export const convertCollectionFromApi = (
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

export const convertGetPremintApiResponse = (
  response: PremintSignatureGetResponse,
) => ({
  ...convertPremintFromApi(response.premint),
  collection: convertCollectionFromApi(response.collection),
  signature: response.signature as Hex,
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
  collection,
  premintConfigVersion,
  premintConfig,
  signature,
  chainId,
}: {
  collection: ContractCreationConfig;
  signature: Hex;
  chainId: number;
} & PremintConfigWithVersion<T>): PremintSignatureRequestBody => ({
  premint: encodePremintForAPI({
    premintConfig,
    premintConfigVersion,
  }),
  signature,
  collection,
  chain_name: networkConfigByChain[chainId]!.zoraBackendChainName,
});
