import { ExtractAbiFunction, AbiParametersToPrimitiveTypes } from "abitype";

import {
  zoraCreator1155PremintExecutorImplABI,
  iPremintDefinitionsABI,
} from "./generated/wagmi";
import { Address } from "viem";

export enum PremintConfigVersion {
  V1 = "1",
  V2 = "2",
  V3 = "3",
}

export type ContractCreationConfig = Omit<
  AbiParametersToPrimitiveTypes<
    ExtractAbiFunction<
      typeof zoraCreator1155PremintExecutorImplABI,
      "premint"
    >["inputs"]
  >[0],
  "additionalAdmins"
> & {
  additionalAdmins: Address[];
};

export type TokenCreationConfigV1 = AbiParametersToPrimitiveTypes<
  ExtractAbiFunction<
    typeof iPremintDefinitionsABI,
    "tokenConfigV1Definition"
  >["inputs"]
>[0];

export type TokenCreationConfigV2 = AbiParametersToPrimitiveTypes<
  ExtractAbiFunction<
    typeof iPremintDefinitionsABI,
    "tokenConfigV2Definition"
  >["inputs"]
>[0];

export type TokenCreationConfigV3 = AbiParametersToPrimitiveTypes<
  ExtractAbiFunction<
    typeof iPremintDefinitionsABI,
    "tokenConfigV3Definition"
  >["inputs"]
>[0];

export type PremintConfigEncoded = AbiParametersToPrimitiveTypes<
  ExtractAbiFunction<
    typeof zoraCreator1155PremintExecutorImplABI,
    "premint"
  >["inputs"]
>[2];

type PremintConfigCommon = Pick<
  PremintConfigEncoded,
  "deleted" | "uid" | "version"
>;

export type PremintConfigV1 = PremintConfigCommon & {
  tokenConfig: TokenCreationConfigV1;
};
export type PremintConfigV2 = PremintConfigCommon & {
  tokenConfig: TokenCreationConfigV2;
};
export type PremintConfigV3 = PremintConfigCommon & {
  tokenConfig: TokenCreationConfigV3;
};

export type PremintMintArguments = AbiParametersToPrimitiveTypes<
  ExtractAbiFunction<
    typeof zoraCreator1155PremintExecutorImplABI,
    "premint"
  >["inputs"]
>[5];

export type PremintConfigForVersion<T extends PremintConfigVersion> =
  T extends PremintConfigVersion.V1
    ? PremintConfigV1
    : T extends PremintConfigVersion.V2
      ? PremintConfigV2
      : PremintConfigV3;

export type PremintConfigWithVersion<T extends PremintConfigVersion> = {
  /** Premint Config */
  premintConfig: PremintConfigForVersion<T>;
  /** PremintConfigVersion of the premint */
  premintConfigVersion: T;
};
export type PremintConfigAndVersion =
  | PremintConfigWithVersion<PremintConfigVersion.V1>
  | PremintConfigWithVersion<PremintConfigVersion.V2>
  | PremintConfigWithVersion<PremintConfigVersion.V3>;

export type PremintConfig = PremintConfigV1 | PremintConfigV2;

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
