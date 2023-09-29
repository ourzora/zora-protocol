import { Address } from "abitype";
import { ExtractAbiFunction, AbiParametersToPrimitiveTypes } from "abitype";
import { zoraCreator1155PremintExecutorImplABI as preminterAbi } from "./wagmiGenerated";
import { TypedDataDefinition } from "viem";

type PremintInputs = ExtractAbiFunction<
  typeof preminterAbi,
  "premint"
>["inputs"];

type PreminterHashDataTypes = AbiParametersToPrimitiveTypes<PremintInputs>;

export type ContractCreationConfig = PreminterHashDataTypes[0];
export type PremintConfig = PreminterHashDataTypes[1];
export type TokenCreationConfig = PremintConfig["tokenConfig"];

// Convenience method to create the structured typed data
// needed to sign for a premint contract and token
export const preminterTypedDataDefinition = ({
  verifyingContract,
  premintConfig,
  chainId,
}: {
  verifyingContract: Address;
  premintConfig: PremintConfig;
  chainId: number;
}) => {
  const { tokenConfig, uid, version, deleted } = premintConfig;
  const types = {
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

  const result: TypedDataDefinition<typeof types, "CreatorAttribution"> = {
    domain: {
      chainId,
      name: "Preminter",
      version: "1",
      verifyingContract: verifyingContract,
    },
    types,
    message: {
      tokenConfig,
      uid,
      version,
      deleted,
    },
    primaryType: "CreatorAttribution",
  };

  // console.log({ result, deleted });

  return result;
};
