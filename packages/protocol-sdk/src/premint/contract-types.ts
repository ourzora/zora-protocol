import { ExtractAbiFunction, AbiParametersToPrimitiveTypes } from "abitype";
import { zoraCreator1155PremintExecutorImplABI as preminterAbi } from "@zoralabs/protocol-deployments";

type PremintV1Inputs = ExtractAbiFunction<
  typeof preminterAbi,
  "premintV1"
>["inputs"];

type PremintV1HashDataTypes = AbiParametersToPrimitiveTypes<PremintV1Inputs>;

export type ContractCreationConfig = PremintV1HashDataTypes[0];

export type PremintConfigV1 = PremintV1HashDataTypes[1];
export type TokenCreationConfigV1 = PremintConfigV1["tokenConfig"];

export type MintArguments = PremintV1HashDataTypes[4];

type PremintV2Inputs = ExtractAbiFunction<
  typeof preminterAbi,
  "premintV2"
>["inputs"];

type PremintV2HashDataTypes = AbiParametersToPrimitiveTypes<PremintV2Inputs>;

export type PremintConfigV2 = PremintV2HashDataTypes[1];
export type TokenCreationConfigV2 = PremintConfigV2["tokenConfig"];

export const v1Types = {
  CreatorAttribution: [
    { name: "tokenConfig", type: "TokenCreationConfig" },
    // unique id scoped to the contract and token to create.
    // ensure that a signature can be replaced, as long as the replacement
    // has the same uid, and a newer version.
    { name: "uid", type: "uint32" },
    { name: "version", type: "uint32" },
    // if this update should result in the signature being deleted.
    { name: "deleted", type: "bool" },
  ],
  TokenCreationConfig: [
    { name: "tokenURI", type: "string" },
    { name: "maxSupply", type: "uint256" },
    { name: "maxTokensPerAddress", type: "uint64" },
    { name: "pricePerToken", type: "uint96" },
    { name: "mintStart", type: "uint64" },
    { name: "mintDuration", type: "uint64" },
    { name: "royaltyMintSchedule", type: "uint32" },
    { name: "royaltyBPS", type: "uint32" },
    { name: "royaltyRecipient", type: "address" },
    { name: "fixedPriceMinter", type: "address" },
  ],
} as const;

export const v2Types = {
  CreatorAttribution: [
    { name: "tokenConfig", type: "TokenCreationConfig" },
    // unique id scoped to the contract and token to create.
    // ensure that a signature can be replaced, as long as the replacement
    // has the same uid, and a newer version.
    { name: "uid", type: "uint32" },
    { name: "version", type: "uint32" },
    // if this update should result in the signature being deleted.
    { name: "deleted", type: "bool" },
  ],
  TokenCreationConfig: [
    { name: "tokenURI", type: "string" },
    { name: "maxSupply", type: "uint256" },
    { name: "maxTokensPerAddress", type: "uint64" },
    { name: "pricePerToken", type: "uint96" },
    { name: "mintStart", type: "uint64" },
    { name: "mintDuration", type: "uint64" },
    { name: "royaltyBPS", type: "uint32" },
    { name: "payoutRecipient", type: "address" },
    { name: "fixedPriceMinter", type: "address" },
    { name: "createReferral", type: "address" },
  ],
} as const;

export const PreminterDomain = "Preminter";

export enum PremintConfigVersion {
  V1 = "1",
  V2 = "2",
}

export type PremintConfigForVersion<T extends PremintConfigVersion> =
  T extends PremintConfigVersion.V1 ? PremintConfigV1 : PremintConfigV2;

export type PremintConfigWithVersion<T extends PremintConfigVersion> = {
  premintConfig: PremintConfigForVersion<T>;
  premintConfigVersion: T;
};

export type PremintConfigAndVersion =
  | PremintConfigWithVersion<PremintConfigVersion.V1>
  | PremintConfigWithVersion<PremintConfigVersion.V2>;

export type PremintConfig = PremintConfigV1 | PremintConfigV2;
export type TokenCreationConfig = TokenCreationConfigV1 | TokenCreationConfigV2;

export type PremintConfigForTokenCreationConfig<T extends TokenCreationConfig> =
  T extends TokenCreationConfigV1 ? PremintConfigV1 : PremintConfigV2;

export type TokenConfigForVersion<T extends PremintConfigVersion> =
  PremintConfigForVersion<T>["tokenConfig"];

export type TokenConfigWithVersion<T extends PremintConfigVersion> = {
  tokenConfig: TokenConfigForVersion<T>;
  premintConfigVersion: T;
};
