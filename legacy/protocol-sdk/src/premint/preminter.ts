import { Address } from "abitype";
import {
  zoraCreator1155PremintExecutorImplABI as preminterAbi,
  zoraCreator1155PremintExecutorImplABI,
  zoraCreator1155PremintExecutorImplAddress,
  ContractCreationConfig,
} from "@zoralabs/protocol-deployments";
import { zeroAddress, parseEther, Account } from "viem";
import { PublicClient } from "src/utils";
import {
  ContractCreationConfigOrAddress,
  ContractCreationConfigWithOptionalAdditionalAdmins,
} from "./contract-types";
import { IPremintGetter } from "./premint-api-client";
import { isPremintConfigV1, isPremintConfigV2 } from "./conversions";
import { MintCosts } from "src/mint/types";

export const getPremintExecutorAddress = () =>
  zoraCreator1155PremintExecutorImplAddress[999] as Address;

export async function isAuthorizedToCreatePremint({
  contractAdmin = zeroAddress,
  additionalAdmins = [],
  collectionAddress,
  publicClient,
  signer,
}: {
  contractAdmin?: Address;
  additionalAdmins?: Address[];
  collectionAddress: Address;
  publicClient: PublicClient;
  signer: Address | Account;
}) {
  // otherwize, we must assume the newer version of premint executor is deployed, so we call that.
  return await publicClient.readContract({
    abi: preminterAbi,
    address: getPremintExecutorAddress(),
    functionName: "isAuthorizedToCreatePremintWithAdditionalAdmins",
    args: [
      typeof signer === "string" ? signer : signer.address,
      contractAdmin,
      collectionAddress,
      additionalAdmins,
    ],
  });
}

export async function getPremintCollectionAddress({
  publicClient,
  contract: collection,
  contractAddress: collectionAddress,
}: {
  publicClient: PublicClient;
} & ContractCreationConfigOrAddress): Promise<Address> {
  if (typeof collection !== "undefined") {
    return publicClient.readContract({
      address: getPremintExecutorAddress(),
      abi: zoraCreator1155PremintExecutorImplABI,
      functionName: "getContractWithAdditionalAdminsAddress",
      args: [
        {
          ...collection,
          additionalAdmins: collection.additionalAdmins || [],
        },
      ],
    });
  }

  return collectionAddress;
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

type GetMintCostsParams = {
  tokenContract: Address;
  tokenPrice: bigint;
  quantityToMint: bigint | number;
  publicClient: PublicClient;
};

export async function getPremintMintCosts({
  publicClient,
  tokenContract,
  tokenPrice,
  quantityToMint,
}: GetMintCostsParams): Promise<MintCosts> {
  const mintFee = await getPremintMintFee({ tokenContract, publicClient });

  const quantityToMintBigInt = BigInt(quantityToMint);

  return {
    mintFee: mintFee * quantityToMintBigInt,
    totalPurchaseCost: tokenPrice * quantityToMintBigInt,
    totalCostEth: (mintFee + tokenPrice) * quantityToMintBigInt,
  };
}
async function getPremintPricePerToken({
  collection,
  uid,
  premintGetter,
}: {
  collection: Address;
  uid: number;
  premintGetter: IPremintGetter;
}) {
  const { premint: premintConfigWithVersion } = await premintGetter.get({
    collectionAddress: collection,
    uid,
  });

  if (
    isPremintConfigV1(premintConfigWithVersion) ||
    isPremintConfigV2(premintConfigWithVersion)
  ) {
    return premintConfigWithVersion.premintConfig.tokenConfig.pricePerToken;
  }

  throw new Error("Premint version not supported to get price");
}

export async function getPremintMintCostsWithUnknownTokenPrice({
  premintGetter,
  uid,
  ...rest
}: Omit<GetMintCostsParams, "tokenPrice"> & {
  premintGetter: IPremintGetter;
  uid: number;
}) {
  const pricePerToken = await getPremintPricePerToken({
    uid,
    premintGetter,
    collection: rest.tokenContract,
  });

  return await getPremintMintCosts({
    ...rest,
    tokenPrice: pricePerToken,
  });
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

export const emptyContractCreationConfig = (): ContractCreationConfig => ({
  contractAdmin: zeroAddress,
  contractURI: "",
  contractName: "",
  additionalAdmins: [],
});

export function defaultAdditionalAdmins(
  collection: ContractCreationConfigWithOptionalAdditionalAdmins,
): ContractCreationConfig {
  return {
    ...collection,
    additionalAdmins: collection.additionalAdmins || [],
  };
}

export const toContractCreationConfigOrAddress = ({
  collection,
  collectionAddress,
}: {
  collection?: ContractCreationConfigWithOptionalAdditionalAdmins;
  collectionAddress?: Address;
}) => {
  if (typeof collection !== "undefined") {
    return {
      contract: collection,
    };
  }

  if (typeof collectionAddress !== "undefined") {
    return {
      contractAddress: collectionAddress,
    };
  }

  throw new Error("Must provide either a collection or a collection address");
};
