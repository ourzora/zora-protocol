import { Address } from "abitype";
import {
  zoraCreator1155PremintExecutorImplABI as preminterAbi,
  zoraCreator1155ImplABI,
  zoraCreator1155PremintExecutorImplABI,
  zoraCreator1155PremintExecutorImplAddress,
  zoraCreatorFixedPriceSaleStrategyAddress,
  premintTypedDataDefinition,
} from "@zoralabs/protocol-deployments";
import {
  recoverTypedDataAddress,
  Hex,
  PublicClient,
  zeroAddress,
  hashDomain,
  keccak256,
  concat,
  recoverAddress,
  GetEventArgs,
  parseEther,
} from "viem";
import {
  ContractCreationConfig,
  PremintConfig,
  PremintConfigForTokenCreationConfig,
  PremintConfigV1,
  PremintConfigV2,
  PremintConfigVersion,
  PremintConfigWithVersion,
  TokenCreationConfig,
} from "@zoralabs/protocol-deployments";
import { MintCosts } from "src/mint/mint-client";

export const getPremintExecutorAddress = () =>
  zoraCreator1155PremintExecutorImplAddress[999] as Address;

export type IsValidSignatureReturn = {
  isAuthorized: boolean;
  recoveredAddress?: Address;
};

export async function isAuthorizedToCreatePremint({
  collection,
  collectionAddress,
  publicClient,
  signer,
}: {
  collection: ContractCreationConfig;
  collectionAddress: Address;
  publicClient: PublicClient;
  signer: Address;
}) {
  if (collection.additionalAdmins.length > 0)
    throw new Error("additionalAdmins not supported yet.");
  // otherwize, we must assume the newer version of premint executor is deployed, so we call that.
  return await publicClient.readContract({
    abi: preminterAbi,
    address: getPremintExecutorAddress(),
    functionName: "isAuthorizedToCreatePremint",
    args: [signer, collection.contractAdmin, collectionAddress],
  });
}

export async function recoverPremintSigner<T extends PremintConfigVersion>({
  signature,
  ...rest
}: {
  signature: Hex;
  chainId: number;
  verifyingContract: Address;
} & PremintConfigWithVersion<T>): Promise<Address> {
  return await recoverTypedDataAddress({
    ...premintTypedDataDefinition(rest),
    signature,
  });
}

export async function tryRecoverPremintSigner(
  params: Parameters<typeof recoverPremintSigner>[0],
) {
  try {
    return await recoverPremintSigner(params);
  } catch (error) {
    console.error(error);
    return undefined;
  }
}

/**
 * Recovers the address from a typed data signature and then checks if the recovered address is authorized to create a premint
 *
 * @param params validationProperties
 * @param params.typedData typed data definition for premint config
 * @param params.signature signature to validate
 * @param params.publicClient public rpc read-only client
 * @param params.premintConfigContractAdmin the original contractAdmin on the ContractCreationConfig for the premint; this is usually the original creator of the premint
 * @param params.tokenContract the address of the 1155 contract
 * @returns
 */
export async function isValidSignature<T extends PremintConfigVersion>({
  signature,
  publicClient,
  collection,
  chainId,
  ...premintConfigAndVersion
}: {
  collection: ContractCreationConfig;
  signature: Hex;
  chainId: number;
  publicClient: PublicClient;
} & PremintConfigWithVersion<T>): Promise<IsValidSignatureReturn> {
  const tokenContract = await getPremintCollectionAddress({
    collection,
    publicClient,
  });
  const recoveredAddress = await tryRecoverPremintSigner({
    ...premintConfigAndVersion,
    signature,
    verifyingContract: tokenContract,
    chainId,
  });

  if (!recoverAddress) {
    return {
      isAuthorized: false,
    };
  }

  const isAuthorized = await isAuthorizedToCreatePremint({
    signer: recoveredAddress!,
    collection,
    collectionAddress: tokenContract,
    publicClient,
  });

  return {
    isAuthorized,
    recoveredAddress,
  };
}

/**
 * Converts a premint config from v1 to v2
 *
 * @param premintConfig premint config to convert
 * @param createReferral address that referred the creator, that will receive create referral rewards for the created token
 */
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

export type CreatorAttributionEventParams = GetEventArgs<
  typeof zoraCreator1155ImplABI,
  "CreatorAttribution",
  { EnableUnion: false }
>;

/**
 * Recovers the address from a CreatorAttribution event emitted from a ZoraCreator1155 contract
 * Useful for verifying that the creator of a token is the one who signed a premint for its creation.
 * 

 * @param creatorAttribution parameters from the CreatorAttribution event
 * @param chainId the chain id of the current chain
 * @param tokenContract the address of the 1155 contract
 * @returns the address of the signer
 */
export const recoverCreatorFromCreatorAttribution = async ({
  creatorAttribution: { version, domainName, structHash, signature },
  chainId,
  tokenContract,
}: {
  creatorAttribution: CreatorAttributionEventParams;
  tokenContract: Address;
  chainId: number;
}) => {
  // hash the eip712 domain based on the parameters emitted from the event:
  const hashedDomain = hashDomain({
    domain: {
      chainId,
      name: domainName,
      verifyingContract: tokenContract,
      version,
    },
    types: {
      EIP712Domain: [
        { name: "name", type: "string" },
        { name: "version", type: "string" },
        {
          name: "chainId",
          type: "uint256",
        },
        {
          name: "verifyingContract",
          type: "address",
        },
      ],
    },
  });

  // re-build the eip-712 typed data hash, consisting of the hashed domain and the structHash emitted from the event:
  const parts: Hex[] = ["0x1901", hashedDomain, structHash!];

  const hashedTypedData = keccak256(concat(parts));

  return await recoverAddress({
    hash: hashedTypedData,
    signature: signature!,
  });
};

export const supportedPremintVersions = async ({
  tokenContract,
  publicClient,
}: {
  tokenContract: Address;
  publicClient: PublicClient;
}): Promise<readonly string[]> => {
  return await publicClient.readContract({
    abi: preminterAbi,
    address: getPremintExecutorAddress(),
    functionName: "supportedPremintSignatureVersions",
    args: [tokenContract],
  });
};
/**
 * Checks if the 1155 contract at that address supports the given version of the premint config.
 */
export const supportsPremintVersion = async ({
  version,
  tokenContract,
  publicClient,
}: {
  version: PremintConfigVersion;
  tokenContract: Address;
  publicClient: PublicClient;
}): Promise<boolean> => {
  return (
    await supportedPremintVersions({ tokenContract, publicClient })
  ).includes(version);
};

export async function getPremintCollectionAddress({
  collection,
  publicClient,
}: {
  collection: ContractCreationConfig;
  publicClient: PublicClient;
}): Promise<Address> {
  return publicClient.readContract({
    address: getPremintExecutorAddress(),
    abi: zoraCreator1155PremintExecutorImplABI,
    functionName: "getContractAddress",
    args: [collection],
  });
}

export function applyUpdateToPremint({
  uid,
  version,
  tokenConfig,
  tokenConfigUpdates,
}: {
  tokenConfig: TokenCreationConfig;
  tokenConfigUpdates: Partial<TokenCreationConfig>;
} & Pick<PremintConfig, "uid" | "version">): PremintConfig {
  const updatedTokenConfig: TokenCreationConfig = {
    ...tokenConfig,
    ...tokenConfigUpdates,
  } as const;

  const result = {
    deleted: false,
    uid,
    version: version + 1,
    tokenConfig: updatedTokenConfig,
  } as PremintConfig;

  return result;
}

export function makeNewPremint<T extends TokenCreationConfig>({
  tokenConfig,
  uid,
}: {
  tokenConfig: T;
  uid: number;
}): PremintConfigForTokenCreationConfig<T> {
  return {
    deleted: false,
    uid,
    version: 0,
    tokenConfig,
  } as PremintConfigForTokenCreationConfig<T>;
}

export async function getPremintMintFee({
  tokenContract,
  publicClient,
}: {
  tokenContract: Address;
  publicClient: PublicClient;
}) {
  // try reading mint fee function from premint executor.  this will revert
  // if the abi is not up to date yet
  try {
    return await publicClient.readContract({
      address: getPremintExecutorAddress(),
      abi: zoraCreator1155PremintExecutorImplABI,
      functionName: "mintFee",
      args: [tokenContract],
    });
  } catch (e) {
    console.error(e);

    return parseEther("0.000777");
  }
}

export async function getPremintMintCosts({
  publicClient,
  tokenContract,
  tokenPrice,
  quantityToMint,
}: {
  tokenContract: Address;
  tokenPrice: bigint;
  quantityToMint: bigint;
  publicClient: PublicClient;
}): Promise<MintCosts> {
  const mintFee = await getPremintMintFee({ tokenContract, publicClient });

  return {
    mintFee: mintFee * quantityToMint,
    tokenPurchaseCost: tokenPrice * quantityToMint,
    totalCost: (mintFee + tokenPrice) * quantityToMint,
  };
}

export function makeMintRewardsRecipient({
  mintReferral = zeroAddress,
  platformReferral = zeroAddress,
}: {
  mintReferral?: Address;
  platformReferral?: Address;
}): Address[] {
  return [mintReferral, platformReferral];
}

export function getDefaultFixedPriceMinterAddress(chainId: number): Address {
  return zoraCreatorFixedPriceSaleStrategyAddress[
    chainId as keyof typeof zoraCreatorFixedPriceSaleStrategyAddress
  ]!;
}
