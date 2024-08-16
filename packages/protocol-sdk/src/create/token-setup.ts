import { zoraCreator1155ImplABI } from "@zoralabs/protocol-deployments";
import { Address, encodeFunctionData, zeroAddress, Hex } from "viem";
import * as semver from "semver";
import { ContractProps, CreateNew1155TokenProps, New1155Token } from "./types";
import { OPEN_EDITION_MINT_SIZE } from "src/constants";
import { getSalesConfigWithDefaults } from "./minter-defaults";
import { setupMinters } from "./minter-setup";

function applyNew1155Defaults(
  props: CreateNew1155TokenProps,
  ownerAddress: Address,
  contractName: string,
): New1155Token {
  const { payoutRecipient: fundsRecipient } = props;
  const fundsRecipientOrOwner =
    fundsRecipient && fundsRecipient !== zeroAddress
      ? fundsRecipient
      : ownerAddress;
  return {
    payoutRecipient: fundsRecipientOrOwner,
    createReferral: props.createReferral || zeroAddress,
    maxSupply:
      typeof props.maxSupply === "undefined"
        ? OPEN_EDITION_MINT_SIZE
        : BigInt(props.maxSupply),
    royaltyBPS: props.royaltyBPS || 1000,
    tokenMetadataURI: props.tokenMetadataURI,
    salesConfig: getSalesConfigWithDefaults(props.salesConfig, contractName),
  };
}

function buildSetupNewToken({
  tokenURI,
  maxSupply = OPEN_EDITION_MINT_SIZE,
  createReferral = zeroAddress,
  contractVersion,
}: {
  tokenURI: string;
  maxSupply: bigint;
  createReferral: Address;
  contractVersion?: string;
}): Hex {
  // If we're adding a new token to an existing contract which doesn't support
  // creator rewards, we won't have the 'setupNewTokenWithCreateReferral' method
  // available, so we need to check for that and use the fallback method instead.
  if (contractSupportsMintRewards(contractVersion, "ERC1155")) {
    return encodeFunctionData({
      abi: zoraCreator1155ImplABI,
      functionName: "setupNewTokenWithCreateReferral",
      args: [tokenURI, BigInt(maxSupply), createReferral],
    });
  }

  if (createReferral !== zeroAddress) {
    throw new Error(
      "Contract does not support create referral, but one was provided",
    );
  }
  return encodeFunctionData({
    abi: zoraCreator1155ImplABI,
    functionName: "setupNewToken",
    args: [tokenURI, BigInt(maxSupply)],
  });
}

function setupRoyaltyConfig({
  royaltyBPS,
  royaltyRecipient,
  nextTokenId,
}: {
  royaltyBPS: number;
  royaltyRecipient: Address;
  nextTokenId: bigint;
}) {
  if (royaltyBPS > 0 && royaltyRecipient != zeroAddress) {
    return encodeFunctionData({
      abi: zoraCreator1155ImplABI,
      functionName: "updateRoyaltiesForToken",
      args: [
        nextTokenId,
        {
          royaltyBPS,
          royaltyRecipient,
          royaltyMintSchedule: 0,
        },
      ],
    });
  }

  return null;
}

function makeAdminMintCall({
  ownerAddress,
  mintQuantity,
  nextTokenId,
}: {
  ownerAddress: Address;
  mintQuantity?: number;
  nextTokenId: bigint;
}) {
  if (!mintQuantity || mintQuantity <= 0 || !ownerAddress) {
    return null;
  }

  return encodeFunctionData({
    abi: zoraCreator1155ImplABI,
    functionName: "adminMint",
    args: [ownerAddress, nextTokenId, BigInt(mintQuantity), zeroAddress],
  });
}

export function constructCreate1155TokenCalls(
  props: CreateNew1155TokenProps &
    ContractProps & {
      ownerAddress: Address;
      chainId: number;
    } & {
      contractName: string;
    },
): {
  setupActions: `0x${string}`[];
  newToken: New1155Token;
  minter: Address;
} {
  const {
    chainId,
    nextTokenId,
    mintToCreatorCount,
    ownerAddress,
    contractVersion,
  } = props;

  const new1155TokenPropsWithDefaults = applyNew1155Defaults(
    props,
    ownerAddress,
    props.contractName,
  );

  const verifyTokenIdExpected = encodeFunctionData({
    abi: zoraCreator1155ImplABI,
    functionName: "assumeLastTokenIdMatches",
    args: [nextTokenId - 1n],
  });

  const setupNewToken = buildSetupNewToken({
    tokenURI: new1155TokenPropsWithDefaults.tokenMetadataURI,
    maxSupply: new1155TokenPropsWithDefaults.maxSupply,
    createReferral: new1155TokenPropsWithDefaults.createReferral,
    contractVersion,
  });

  const royaltyConfig = setupRoyaltyConfig({
    royaltyBPS: new1155TokenPropsWithDefaults.royaltyBPS,
    royaltyRecipient: new1155TokenPropsWithDefaults.payoutRecipient,
    nextTokenId,
  });

  const { minter, setupActions: mintersSetup } = setupMinters({
    tokenId: nextTokenId,
    chainId,
    fundsRecipient: new1155TokenPropsWithDefaults.payoutRecipient,
    salesConfig: new1155TokenPropsWithDefaults.salesConfig,
  });

  const adminMintCall = makeAdminMintCall({
    ownerAddress,
    mintQuantity: mintToCreatorCount,
    nextTokenId,
  });

  const setupActions = [
    verifyTokenIdExpected,
    setupNewToken,
    ...mintersSetup,
    royaltyConfig,
    adminMintCall,
  ].filter((item) => item !== null) as `0x${string}`[];

  return {
    setupActions,
    minter,
    newToken: new1155TokenPropsWithDefaults,
  };
}

export const contractSupportsMintRewards = (
  contractVersion?: string | null,
  contractStandard?: "ERC721" | "ERC1155",
) => {
  if (!contractStandard || !contractVersion) {
    return false;
  }

  // Try force-convert version format to semver format
  const semVerContractVersion = semver.coerce(contractVersion)?.raw;
  if (!semVerContractVersion) return false;

  if (contractStandard === "ERC1155") {
    return semver.gte(semVerContractVersion, "1.3.5");
  } else {
    return semver.gte(semVerContractVersion, "14.0.0");
  }
};
