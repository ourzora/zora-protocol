import { Address } from "abitype";
import { ExtractAbiFunction, AbiParametersToPrimitiveTypes } from "abitype";
import { zoraCreatorSignatureMinterStrategyABI as signatureMinterAbi } from "./wagmiGenerated";
import { TypedDataDefinition } from "viem";

type SignatureMinterHashTypeDataInputs = ExtractAbiFunction<
  typeof signatureMinterAbi,
  "delegateCreateContractHashTypeData"
>["inputs"];

type SignatureMinterHashTypeDataTypes =
  AbiParametersToPrimitiveTypes<SignatureMinterHashTypeDataInputs>;

export type SignatureMinterHashTypeDataConfig =
  SignatureMinterHashTypeDataTypes;

type SignatureMinterEncodeMinterArgumentsInputs = ExtractAbiFunction<
  typeof signatureMinterAbi,
  "encodeMinterArguments"
>["inputs"];

type SignatureMinterEncodeMinterArgumentsDataTypes =
  AbiParametersToPrimitiveTypes<SignatureMinterEncodeMinterArgumentsInputs>;

export type SignatureMinterEncodeMinterArgumentsConfig =
  SignatureMinterEncodeMinterArgumentsDataTypes[0];

// Convenience method to create the structured typed data
// needed to sign for a signature mint
export const signatureMinterTypedDataDefinition = ({
  verifyingContract,
  signatureMinterConfig,
  chainId,
}: {
  verifyingContract: Address;
  signatureMinterConfig: SignatureMinterHashTypeDataConfig;
  chainId: number;
}) => {
  const [
    target,
    tokenId,
    nonce,
    quantity,
    pricePerToken,
    expiration,
    mintTo,
    fundsRecipient,
  ] = signatureMinterConfig;
  const types = {
    requestMint: [
      { name: "target", type: "address" },
      { name: "tokenId", type: "uint256" },
      { name: "nonce", type: "bytes32" },
      { name: "quantity", type: "uint256" },
      { name: "pricePerToken", type: "uint256" },
      { name: "expiration", type: "uint256" },
      { name: "mintTo", type: "address" },
      { name: "fundsRecipient", type: "address" },
    ],
  };

  const result: TypedDataDefinition<typeof types, "requestMint"> = {
    domain: {
      chainId,
      name: "ZoraSignatureMinterStrategy",
      version: "1",
      verifyingContract: verifyingContract,
    },
    types,
    message: {
      target,
      tokenId,
      nonce,
      quantity,
      pricePerToken,
      expiration,
      mintTo,
      fundsRecipient,
    },
    primaryType: "requestMint",
  };

  return result;
};
