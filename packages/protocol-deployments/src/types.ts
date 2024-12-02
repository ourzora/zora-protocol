import { ExtractAbiFunction, AbiParametersToPrimitiveTypes } from "abitype";

import {
  zoraCreator1155PremintExecutorImplABI,
  iPremintDefinitionsABI,
  sponsoredSparksSpenderABI,
} from "./generated/wagmi";
import { Address } from "viem";

import { commentsABI, callerAndCommenterABI } from "./generated/wagmi";

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

export type SponsoredSparksBatch = AbiParametersToPrimitiveTypes<
  ExtractAbiFunction<
    typeof sponsoredSparksSpenderABI,
    "hashSponsoredMint"
  >["inputs"]
>[0];

export type CommentIdentifier = AbiParametersToPrimitiveTypes<
  ExtractAbiFunction<typeof commentsABI, "hashCommentIdentifier">["inputs"]
>[0];

export const emptyCommentIdentifier = (): CommentIdentifier => {
  const zeroAddress = "0x0000000000000000000000000000000000000000";
  const zeroHash =
    "0x0000000000000000000000000000000000000000000000000000000000000000";
  return {
    commenter: zeroAddress,
    contractAddress: zeroAddress,
    tokenId: 0n,
    nonce: zeroHash,
  };
};

/**
 * The PermitComment type represents the data structure for a permit comment,
 * for cross-chain commenting, where a user can sign a comment message on one chain,
 * which can then be submitted by anyone on the destination chain to execute the comment action.
 *
 * The permit includes details such as the comment text, the commenter's address,
 * the comment being replied to, and chain IDs for the source and destination chains.
 */
export type PermitComment = AbiParametersToPrimitiveTypes<
  ExtractAbiFunction<typeof commentsABI, "hashPermitComment">["inputs"]
>[0];

/**
 * The PermitSparkComment type represents the data structure for a permit spark comment,
 * for cross-chain sparking (liking with value) of comments, where a user can sign a spark comment message on one chain,
 * which can then be submitted by anyone on the destination chain to execute the spark action.
 *
 * The permit includes details such as the comment to be sparked, the sparker's address,
 * the quantity of sparks, and chain IDs for the source and destination chains.
 */
export type PermitSparkComment = AbiParametersToPrimitiveTypes<
  ExtractAbiFunction<typeof commentsABI, "hashPermitSparkComment">["inputs"]
>[0];

/**
 * The PermitTimedSaleMintAndComment type represents the data structure for a permit timed sale mint and comment,
 * where a user can sign a message to mint during a timed sale and leave a comment in a single transaction.
 * This can be executed on the destination chain by anyone.
 *
 * The permit includes details such as the minting parameters, comment text, and chain IDs for the source and destination chains.
 */
export type PermitMintAndComment = AbiParametersToPrimitiveTypes<
  ExtractAbiFunction<
    typeof callerAndCommenterABI,
    "hashPermitTimedSaleMintAndComment"
  >["inputs"]
>[0];

/**
 * The PermitBuyOnSecondaryAndComment type represents the data structure for a permit buy on secondary market and comment,
 * where a user can sign a message to buy on secondary market and leave a comment in a single transaction.
 * This can be executed on the destination chain by anyone.
 */
export type PermitBuyOnSecondaryAndComment = AbiParametersToPrimitiveTypes<
  ExtractAbiFunction<
    typeof callerAndCommenterABI,
    "hashPermitBuyOnSecondaryAndComment"
  >["inputs"]
>[0];
