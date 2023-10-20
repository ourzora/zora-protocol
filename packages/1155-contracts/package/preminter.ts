import { Address } from "abitype";
import { ExtractAbiFunction, AbiParametersToPrimitiveTypes } from "abitype";
import { zoraCreator1155PremintExecutorImplABI as preminterAbi } from "./wagmiGenerated";
import { TypedDataDefinition, encodeAbiParameters } from "viem";

type PremintInputs = ExtractAbiFunction<
  typeof preminterAbi,
  "premint"
>["inputs"];

type PreminterHashDataTypes = AbiParametersToPrimitiveTypes<PremintInputs>;

export type ContractCreationConfig = PreminterHashDataTypes[0];
export type PremintConfigs = PreminterHashDataTypes[1];

export type TokenCreationConfigV1 = PremintConfigV2["tokenConfig"];
export type PremintConfigV2 = Extract<
  PremintConfigs,
  {
    tokenConfig: {
      createReferral: string;
    };
  }
>;
export type PremintConfigV1 = Exclude<PremintConfigs, PremintConfigV2>;
export type TokenCreationConfigV2 = PremintConfigV2["tokenConfig"];

const premintV2Types = {
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
    { name: "royaltyRecipient", type: "address" },
    { name: "fixedPriceMinter", type: "address" },
    { name: "createReferral", type: "address" },
  ],
};

// Convenience method to create the structured typed data
// needed to sign for a premint contract and token
export const preminterTypedDataDefinitionV2 = ({
  verifyingContract,
  premintConfig,
  chainId,
}: {
  verifyingContract: Address;
  premintConfig: PremintConfigV2;
  chainId: number;
}) => {
  const { tokenConfig, uid, version, deleted } = premintConfig;

  const result: TypedDataDefinition<
    typeof premintV2Types,
    "CreatorAttribution"
  > = {
    domain: {
      chainId,
      name: "Preminter",
      version: "2",
      verifyingContract: verifyingContract,
    },
    types: premintV2Types,
    message: {
      tokenConfig,
      uid,
      version,
      deleted,
    },
    primaryType: "CreatorAttribution",
  };

  return result;
};

const premintV1Types = {
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
};

// Convenience method to create the structured typed data
// needed to sign for a premint contract and token
export const preminterTypedDataDefinitionV1 = ({
  verifyingContract,
  premintConfig,
  chainId,
}: {
  verifyingContract: Address;
  premintConfig: PremintConfigV1;
  chainId: number;
}) => {
  const { tokenConfig, uid, version, deleted } = premintConfig;

  const result: TypedDataDefinition<
    typeof premintV1Types,
    "CreatorAttribution"
  > = {
    domain: {
      chainId,
      name: "Preminter",
      version: "1",
      verifyingContract: verifyingContract,
    },
    types: premintV1Types,
    message: {
      tokenConfig,
      uid,
      version,
      deleted,
    },
    primaryType: "CreatorAttribution",
  };

  return result;
};

const zeroAddress: Address = "0x0000000000000000000000000000000000000000";

export const encodeMintArguments = ({
  mintComment = "",
  mintReferral = zeroAddress,
}: {
  mintComment?: string;
  mintReferral?: Address;
}) => {
  return encodeAbiParameters(
    [
      { name: "mintReferral", type: "address" },
      { name: "mintComment", type: "string" },
    ],
    [mintReferral, mintComment]
  );
};
