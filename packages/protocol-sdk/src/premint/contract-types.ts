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
