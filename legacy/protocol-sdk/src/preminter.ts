import { Address } from "abitype";
import { ExtractAbiFunction, AbiParametersToPrimitiveTypes } from "abitype";
import {
  zoraCreator1155PremintExecutorImplABI as preminterAbi,
  zoraCreator1155PremintExecutorImplAddress,
} from "@zoralabs/protocol-deployments";
import {
  TypedDataDefinition,
  recoverTypedDataAddress,
  Hex,
  PublicClient,
} from "viem";

type PremintInputs = ExtractAbiFunction<
  typeof preminterAbi,
  "premintV1"
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

  return result;
};

export async function isValidSignatureV1({
  contractAddress,
  originalContractAdmin,
  premintConfig,
  signature,
  chainId,
  publicClient,
}: {
  contractAddress: Address;
  originalContractAdmin: Address;
  premintConfig: PremintConfig;
  signature: Hex;
  chainId: number;
  publicClient: PublicClient;
}): Promise<{
  isAuthorized: boolean;
  recoveredAddress?: Address;
}> {
  const typedData = preminterTypedDataDefinition({
    verifyingContract: contractAddress,
    premintConfig,
    chainId,
  });

  // recover the address from the signature
  let recoveredAddress: Address;

  try {
    recoveredAddress = await recoverTypedDataAddress({
      ...typedData,
      signature,
    });
  } catch (error) {
    console.error(error);

    return {
      isAuthorized: false,
    };
  }

  // premint executor is same address on all chains
  const premintExecutorAddress = zoraCreator1155PremintExecutorImplAddress[999];

  const isAuthorized = await publicClient.readContract({
    abi: preminterAbi,
    address: premintExecutorAddress,
    functionName: "isAuthorizedToCreatePremint",
    args: [recoveredAddress, originalContractAdmin, contractAddress],
  });

  return {
    isAuthorized,
    recoveredAddress,
  };
}
