import { Address } from "abitype";
import { ExtractAbiFunction, AbiParametersToPrimitiveTypes } from "abitype";
import {
  zoraCreator1155PreminterABI as preminterAbi,
} from "./wagmiGenerated";
import { TypedDataDefinition } from "viem";

type PreminterHashInputs = ExtractAbiFunction<
  typeof preminterAbi,
  "premintHashData"
>["inputs"];

type PreminterHashDataTypes =
  AbiParametersToPrimitiveTypes<PreminterHashInputs>;

export type ContractCreationConfig = PreminterHashDataTypes[0];
export type TokenCreationConfig = PreminterHashDataTypes[1];

// Convenience method to create the structured typed data
// needed to sign for a premint contract and token
export const preminterTypedDataDefinition = ({
  preminterAddress,
  contractConfig,
  tokenConfig,
  chainId,
}: {
  preminterAddress: Address;
  contractConfig: ContractCreationConfig;
  tokenConfig: TokenCreationConfig;
  chainId: number;
}) => {
  const types = {
    ContractAndToken: [
      { name: "contractConfig", type: "ContractCreationConfig" },
      { name: "tokenConfig", type: "TokenCreationConfig" },
    ],
    ContractCreationConfig: [
      { name: "contractAdmin", type: "address" },
      { name: "contractURI", type: "string" },
      { name: "contractName", type: "string" },
      { name: "royaltyMintSchedule", type: "uint32" },
      { name: "royaltyBPS", type: "uint32" },
      { name: "royaltyRecipient", type: "address" },
    ],
    TokenCreationConfig: [
      { name: "tokenURI", type: "string" },
      { name: "maxSupply", type: "uint256" },
      { name: "maxTokensPerAddress", type: "uint64" },
      { name: "pricePerToken", type: "uint96" },
      { name: "saleDuration", type: "uint64" },
    ],
  };

  const result: TypedDataDefinition<typeof types, "TokenCreationConfig"> = {
    domain: {
      chainId,
      name: "Preminter",
      version: "0.0.1",
      verifyingContract: preminterAddress,
    },
    types,
    message: {
      contractConfig,
      tokenConfig,
    },
    primaryType: "ContractAndToken",
  };

  return result;
};