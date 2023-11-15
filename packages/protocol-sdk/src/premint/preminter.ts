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
  zeroAddress,
} from "viem";

type PremintV1Inputs = ExtractAbiFunction<
  typeof preminterAbi,
  "premintV1"
>["inputs"];

type PremintV1HashDataTypes = AbiParametersToPrimitiveTypes<PremintV1Inputs>;

export type ContractCreationConfig = PremintV1HashDataTypes[0];

export type PremintConfigV1 = PremintV1HashDataTypes[1];
export type TokenCreationConfigV1 = PremintConfigV1["tokenConfig"];

type PremintV2Inputs = ExtractAbiFunction<
  typeof preminterAbi,
  "premintV2"
>["inputs"];

type PremintV2HashDataTypes = AbiParametersToPrimitiveTypes<PremintV2Inputs>;

export type PremintConfigV2 = PremintV2HashDataTypes[1];
export type TokenCreationConfigV2 = PremintConfigV2["tokenConfig"];

const v1Types = {
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
} as const;

const v2Types = {
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
    { name: "payoutRecipient", type: "address" },
    { name: "fixedPriceMinter", type: "address" },
    { name: "createReferral", type: "address" },
  ],
} as const;

const PreminterDomain = "Preminter";

type PremintConfigVersion = "1" | "2";

export const PremintConfigVersion = {
  V1: "1",
  V2: "2",
} as const;


type PremintConfigForVersion<T extends PremintConfigVersion> = T extends "1" ? PremintConfigV1 : PremintConfigV2;

type PremintConfigWithVersion<T extends PremintConfigVersion> = {
  premintConfig: PremintConfigForVersion<T>,
  premintConfigVersion: T
}

export type PremintConfigAndVersion = PremintConfigWithVersion<"1"> | PremintConfigWithVersion<"2">;

// Convenience method to create the structured typed data
// needed to sign for a premint contract and token
export const premintTypedDataDefinition = ({
  verifyingContract,
  chainId,
  premintConfigVersion: version,
  premintConfig,
}: {
  verifyingContract: Address;
  chainId: number;
} & PremintConfigAndVersion): TypedDataDefinition => {
  if (version === PremintConfigVersion.V1)
    return {
      domain: {
        chainId,
        name: PreminterDomain,
        version: PremintConfigVersion.V1,
        verifyingContract: verifyingContract,
      },
      types: v1Types,
      message: premintConfig,
      primaryType: "CreatorAttribution",
    } satisfies TypedDataDefinition<typeof v1Types, "CreatorAttribution">;
  if (version === PremintConfigVersion.V2) {
    return {
      domain: {
        chainId,
        name: PreminterDomain,
        version: PremintConfigVersion.V2,
        verifyingContract: verifyingContract,
      },
      types: v2Types,
      message: premintConfig,
      primaryType: "CreatorAttribution",
    } satisfies TypedDataDefinition<typeof v2Types, "CreatorAttribution">;
  }

  throw new Error(`Invalid version ${version}`);
};

export type IsValidSignatureReturn = {
  isAuthorized: boolean;
  recoveredAddress?: Address;
};

export async function isValidSignature({
  contractAddress,
  originalContractAdmin,
  signature,
  chainId,
  publicClient,
  ...premintConfigAndVersion
}: {
  contractAddress: Address;
  originalContractAdmin: Address;
  signature: Hex;
  chainId: number;
  publicClient: PublicClient;
} & PremintConfigAndVersion): Promise<IsValidSignatureReturn> {
  const typedData = premintTypedDataDefinition({
    verifyingContract: contractAddress,
    chainId,
    ...premintConfigAndVersion
  });

  return await recoverAndValidateSignature({
    typedData,
    signature,
    publicClient,
    originalContractAdmin,
    contractAddress,
    chainId,
  });
}

export async function recoverAndValidateSignature({
  typedData,
  signature,
  publicClient,
  originalContractAdmin,
  contractAddress,
}: {
  contractAddress: Address;
  originalContractAdmin: Address;
  typedData: TypedDataDefinition;
  signature: Hex;
  chainId: number;
  publicClient: PublicClient;
}): Promise<IsValidSignatureReturn> {
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

// Takes a premint config v1 and migrates it to
// version 2, adding the createReferral field
export function migratePremintConfigToV2({
  premintConfig,
  createReferral = zeroAddress,
}: {
  premintConfig: PremintConfigV1;
  createReferral: Address;
}): PremintConfigV2 {
  return {
    ...premintConfig,
    tokenConfig: {
      tokenURI: premintConfig.tokenConfig.tokenURI,
      maxSupply: premintConfig.tokenConfig.maxSupply,
      maxTokensPerAddress: premintConfig.tokenConfig.maxTokensPerAddress,
      pricePerToken: premintConfig.tokenConfig.pricePerToken,
      mintStart: premintConfig.tokenConfig.mintStart,
      mintDuration: premintConfig.tokenConfig.mintDuration,
      payoutRecipient: premintConfig.tokenConfig.royaltyRecipient,
      royaltyBPS: premintConfig.tokenConfig.royaltyBPS,
      fixedPriceMinter: premintConfig.tokenConfig.fixedPriceMinter,
      createReferral,
    },
  };
}
