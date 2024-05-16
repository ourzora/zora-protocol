import { ExtractAbiFunction, AbiParametersToPrimitiveTypes } from "abitype";

import { zoraCreator1155PremintExecutorImplABI } from "./generated/wagmi";

export enum PremintConfigVersion {
  V1 = "1",
  V2 = "2",
  V3 = "3",
}

export type ContractCreationConfig = AbiParametersToPrimitiveTypes<
  ExtractAbiFunction<
    typeof zoraCreator1155PremintExecutorImplABI,
    "premintNewContract"
  >["inputs"]
>[0];

export type PremintConfigV1 = AbiParametersToPrimitiveTypes<
  ExtractAbiFunction<
    typeof zoraCreator1155PremintExecutorImplABI,
    "premintV1Definition"
  >["inputs"]
>[0];
export type PremintConfigV2 = AbiParametersToPrimitiveTypes<
  ExtractAbiFunction<
    typeof zoraCreator1155PremintExecutorImplABI,
    "premintV2Definition"
  >["inputs"]
>[0];
export type PremintConfigV3 = AbiParametersToPrimitiveTypes<
  ExtractAbiFunction<
    typeof zoraCreator1155PremintExecutorImplABI,
    "premintV3Definition"
  >["inputs"]
>[0];

export type PremintMintArguments = AbiParametersToPrimitiveTypes<
  ExtractAbiFunction<
    typeof zoraCreator1155PremintExecutorImplABI,
    "premintNewContract"
  >["inputs"]
>[5];

export type PremintConfigForVersion<T extends PremintConfigVersion> =
  T extends PremintConfigVersion.V1
    ? PremintConfigV1
    : T extends PremintConfigVersion.V2
      ? PremintConfigV2
      : PremintConfigV3;

export type PremintConfigWithVersion<T extends PremintConfigVersion> = {
  premintConfig: PremintConfigForVersion<T>;
  premintConfigVersion: T;
};
export type PremintConfigAndVersion =
  | PremintConfigWithVersion<PremintConfigVersion.V1>
  | PremintConfigWithVersion<PremintConfigVersion.V2>
  | PremintConfigWithVersion<PremintConfigVersion.V3>;

export type PremintConfig = PremintConfigV1 | PremintConfigV2;

export type TokenCreationConfigV1 = PremintConfigV1["tokenConfig"];
export type TokenCreationConfigV2 = PremintConfigV2["tokenConfig"];
export type TokenCreationConfigV3 = PremintConfigV3["tokenConfig"];

export type TokenCreationConfig =
  | TokenCreationConfigV1
  | TokenCreationConfigV2
  | TokenCreationConfigV3;

export type PremintConfigForTokenCreationConfig<T extends TokenCreationConfig> =
  T extends TokenCreationConfigV1
    ? PremintConfigV1
    : T extends TokenCreationConfigV2
      ? PremintConfigV2
      : PremintConfigV3;

export type TokenConfigForVersion<T extends PremintConfigVersion> =
  PremintConfigForVersion<T>["tokenConfig"];

export type TokenConfigWithVersion<T extends PremintConfigVersion> = {
  tokenConfig: TokenConfigForVersion<T>;
  premintConfigVersion: T;
};
