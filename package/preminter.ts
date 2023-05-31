import { Address } from "abitype";
import { ExtractAbiFunction, AbiParametersToPrimitiveTypes } from "abitype";
import { zoraCreator1155PreminterABI as preminterAbi } from "./wagmiGenerated";
import { TypedDataDefinition } from "viem";

type PreminterHashInputs = ExtractAbiFunction<
  typeof preminterAbi,
  "premintHashData"
>["inputs"];

type PreminterHashDataTypes =
  AbiParametersToPrimitiveTypes<PreminterHashInputs>;

export type PremintConfig = PreminterHashDataTypes[0];
export type ContractCreationConfig = PremintConfig["contractConfig"];
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
  const { contractConfig, tokenConfig, uid, version, deleted } = premintConfig;
  const types = {
    Premint: [
      { name: "contractConfig", type: "ContractCreationConfig" },
      { name: "tokenConfig", type: "TokenCreationConfig" },
      { name: "uid", type: "uint32" },
      { name: "version", type: "uint32" },
      { name: "deleted", type: "bool" },
    ],
    ContractCreationConfig: [
      { name: "contractAdmin", type: "address" },
      { name: "contractURI", type: "string" },
      { name: "contractName", type: "string" },
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
    ],
  };

  const result: TypedDataDefinition<typeof types, "Premint"> = {
    domain: {
      chainId,
      name: "Preminter",
      version: "0.0.1",
      verifyingContract: verifyingContract,
    },
    types,
    message: {
      contractConfig,
      tokenConfig,
      uid,
      version,
      deleted,
    },
    primaryType: "Premint",
  };

  // console.log({ result, deleted });

  return result;
};
