import {
  Address,
  TypedDataDomain,
  TypedData,
  TypedDataToPrimitiveTypes,
} from "abitype";
import {
  Hex,
  TypedDataDefinition,
  encodeAbiParameters,
  getAbiItem,
  keccak256,
  toHex,
} from "viem";
import {
  zoraMints1155Address,
  iPremintDefinitionsABI,
} from "./generated/wagmi";
import {
  PremintConfigEncoded,
  PremintConfigV1,
  PremintConfigV2,
  PremintConfigVersion,
  PremintConfigWithVersion,
  TokenConfigWithVersion,
  TokenCreationConfigV1,
  TokenCreationConfigV2,
  TokenCreationConfigV3,
} from "./types";

const premintTypedDataDomain = ({
  chainId,
  version,
  creator1155Contract: verifyingContract,
}: {
  chainId: number;
  version: PremintConfigVersion;
  creator1155Contract: Address;
}): TypedDataDomain => ({
  chainId,
  name: "Preminter",
  version,
  verifyingContract,
});

const premintV1TypedDataType = {
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
} as const satisfies TypedData;

const encodeTokenConfigV1 = (config: TokenCreationConfigV1) => {
  const abiItem = getAbiItem({
    abi: iPremintDefinitionsABI,
    name: "tokenConfigV1Definition",
  });

  return encodeAbiParameters(abiItem.inputs, [config]);
};

const encodeTokenConfigV2 = (config: TokenCreationConfigV2) => {
  const abiItem = getAbiItem({
    abi: iPremintDefinitionsABI,
    name: "tokenConfigV2Definition",
  });

  return encodeAbiParameters(abiItem.inputs, [config]);
};

const encodeTokenConfigV3 = (config: TokenCreationConfigV3) => {
  const abiItem = getAbiItem({
    abi: iPremintDefinitionsABI,
    name: "tokenConfigV3Definition",
  });

  return encodeAbiParameters(abiItem.inputs, [config]);
};

const encodeTokenConfig = <T extends PremintConfigVersion>({
  tokenConfig,
  premintConfigVersion,
}: TokenConfigWithVersion<T>): Hex => {
  if (premintConfigVersion === PremintConfigVersion.V1) {
    return encodeTokenConfigV1(tokenConfig as TokenCreationConfigV1);
  }
  if (premintConfigVersion === PremintConfigVersion.V2) {
    return encodeTokenConfigV2(tokenConfig as TokenCreationConfigV2);
  }
  if (premintConfigVersion === PremintConfigVersion.V3) {
    return encodeTokenConfigV3(tokenConfig as TokenCreationConfigV3);
  }

  throw new Error("Invalid PremintConfigVersion: " + premintConfigVersion);
};

export const encodePremintConfig = <T extends PremintConfigVersion>({
  premintConfig,
  premintConfigVersion,
}: PremintConfigWithVersion<T>): PremintConfigEncoded => {
  const encodedTokenConfig = encodeTokenConfig({
    premintConfigVersion,
    tokenConfig: premintConfig.tokenConfig,
  });

  return {
    deleted: premintConfig.deleted,
    uid: premintConfig.uid,
    version: premintConfig.version,
    premintConfigVersion: keccak256(toHex(premintConfigVersion)),
    tokenConfig: encodedTokenConfig,
  };
};

/**
 * Builds a typed data definition for a PremintConfigV1 to be signed
 * @returns
 */
export const premintV1TypedDataDefinition = ({
  chainId,
  creator1155Contract,
  message,
}: {
  chainId: number;
  creator1155Contract: Address;
  message: PremintConfigV1;
}): TypedDataDefinition<
  typeof premintV1TypedDataType,
  "CreatorAttribution"
> => ({
  types: premintV1TypedDataType,
  primaryType: "CreatorAttribution",
  domain: premintTypedDataDomain({
    chainId,
    version: PremintConfigVersion.V1,
    creator1155Contract,
  }),
  message,
});

const premintV2TypedDataType = {
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
} as const satisfies TypedData;

/**
 * Builds a typed data definition for a PremintConfigV2 to be signed
 */
export const premintV2TypedDataDefinition = ({
  chainId,
  creator1155Contract,
  message,
}: {
  chainId: number;
  creator1155Contract: Address;
  message: PremintConfigV2;
}): TypedDataDefinition<
  typeof premintV2TypedDataType,
  "CreatorAttribution"
> => ({
  types: premintV2TypedDataType,
  primaryType: "CreatorAttribution",
  domain: premintTypedDataDomain({
    chainId,
    version: PremintConfigVersion.V2,
    creator1155Contract,
  }),
  message,
});

export type PremintTypeDataDefinitionParams<T extends PremintConfigVersion> = {
  verifyingContract: Address;
  chainId: number;
} & PremintConfigWithVersion<T>;

/**
 * Creates a typed data definition for a premint config.  Works for all versions of the premint config by specifying the premintConfigVersion.
 *
 * @param params.verifyingContract the address of the 1155 contract
 * @param params.chainId the chain id the premint is signed for
 * @param params.premintConfigVersion the version of the premint config
 * @param params.premintConfig the premint config
 * @returns
 */
export const premintTypedDataDefinition = <T extends PremintConfigVersion>({
  verifyingContract,
  chainId,
  premintConfigVersion: version,
  premintConfig,
}: PremintTypeDataDefinitionParams<T>): TypedDataDefinition => {
  if (version === PremintConfigVersion.V1)
    return premintV1TypedDataDefinition({
      chainId,
      creator1155Contract: verifyingContract,
      message: premintConfig as PremintConfigV1,
    });
  if (version === PremintConfigVersion.V2) {
    return premintV2TypedDataDefinition({
      chainId,
      creator1155Contract: verifyingContract,
      message: premintConfig as PremintConfigV2,
    });
  }

  throw new Error(`Invalid version ${version}`);
};

const permitSafeTransferTypedDataType = {
  PermitSafeTransfer: [
    { name: "owner", type: "address" },
    { name: "to", type: "address" },
    { name: "tokenId", type: "uint256" },
    { name: "quantity", type: "uint256" },
    { name: "safeTransferData", type: "bytes" },
    { name: "nonce", type: "uint256" },
    { name: "deadline", type: "uint256" },
  ],
} as const;

/**
 * Builds a typed data definition for a PermitSafeTransfer on the Mints1155 contract to be signed
 */
export const mintsSafeTransferTypedDataDefinition = ({
  chainId,
  message,
}: {
  chainId: keyof typeof zoraMints1155Address;
  message: TypedDataToPrimitiveTypes<
    typeof permitSafeTransferTypedDataType
  >["PermitSafeTransfer"];
}): TypedDataDefinition<
  typeof permitSafeTransferTypedDataType,
  "PermitSafeTransfer"
> => ({
  types: permitSafeTransferTypedDataType,
  message,
  primaryType: "PermitSafeTransfer",
  domain: {
    chainId,
    name: "Mints",
    version: "1",
    verifyingContract: zoraMints1155Address[chainId],
  },
});

const permitSafeBatchTransferTypedDataType = {
  Permit: [
    {
      name: "owner",
      type: "address",
    },
    {
      name: "to",
      type: "address",
    },
    {
      name: "tokenIds",
      type: "uint256[]",
    },
    {
      name: "quantities",
      type: "uint256[]",
    },
    {
      name: "safeTransferData",
      type: "bytes",
    },
    {
      name: "nonce",
      type: "uint256",
    },
    {
      name: "deadline",
      type: "uint256",
    },
  ],
} as const;

/**
 * Builds a typed data definition for a PermitSafeTransferBatch on the Mints1155 contract to be signed
 * @returns
 */
export const mintsSafeTransferBatchTypedDataDefinition = ({
  chainId,
  message,
}: {
  chainId: keyof typeof zoraMints1155Address;
  message: TypedDataToPrimitiveTypes<
    typeof permitSafeBatchTransferTypedDataType
  >["Permit"];
}): TypedDataDefinition<
  typeof permitSafeBatchTransferTypedDataType,
  "Permit"
> => ({
  types: permitSafeBatchTransferTypedDataType,
  message,
  primaryType: "Permit",
  domain: {
    chainId,
    name: "Mints",
    version: "1",
    verifyingContract: zoraMints1155Address[chainId],
  },
});
