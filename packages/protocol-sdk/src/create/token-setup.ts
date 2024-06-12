import {
  erc20MinterABI,
  erc20MinterAddress as erc20MinterAddresses,
  zoraCreator1155ImplABI,
  zoraCreatorFixedPriceSaleStrategyABI,
  zoraCreatorFixedPriceSaleStrategyAddress,
} from "@zoralabs/protocol-deployments";
import { Address, encodeFunctionData, zeroAddress, Hex } from "viem";
import * as semver from "semver";
import {
  ContractProps,
  CreateNew1155TokenProps,
  New1155Token,
  SalesConfigParamsType,
} from "./types";
import { OPEN_EDITION_MINT_SIZE } from "src/constants";
import { Concrete } from "src/utils";

export const PERMISSION_BITS = {
  MINTER: 2n ** 2n,
};

type SetupMintersProps = {
  tokenId: bigint;
  chainId: number;
  fundsRecipient: Address;
  salesConfig: Concrete<SalesConfigParamsType>;
};

// Sales end forever amount (uint64 max)

const saleSettingsOrDefault = (
  saleSettings?: SalesConfigParamsType,
): Concrete<SalesConfigParamsType> => {
  const SALE_END_FOREVER = 18446744073709551615n;

  const DEFAULT_SALE_SETTINGS: Concrete<SalesConfigParamsType> = {
    currency: zeroAddress,
    // Free Mint
    pricePerToken: 0n,
    // Sale start time – defaults to beginning of unix time
    saleStart: 0n,
    // This is the end of uint64, plenty of time
    saleEnd: SALE_END_FOREVER,
    // 0 Here means no limit
    maxTokensPerAddress: 0n,
  };
  return {
    ...DEFAULT_SALE_SETTINGS,
    ...saleSettings,
  };
};

function applyNew1155Defaults(
  props: CreateNew1155TokenProps,
  ownerAddress: Address,
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
    salesConfig: saleSettingsOrDefault(props.salesConfig),
    tokenMetadataURI: props.tokenMetadataURI,
  };
}

type SetupErc20MinterProps = {
  chainId: number;
  tokenId: bigint;
  fundsRecipient: Address;
} & Concrete<SalesConfigParamsType>;

function setupErc20Minter({
  pricePerToken,
  chainId,
  tokenId: nextTokenId,
  currency,
  saleStart,
  saleEnd,
  maxTokensPerAddress: mintLimit,
  fundsRecipient,
}: SetupErc20MinterProps): {
  minter: Address;
  setupActions: Hex[];
} {
  const erc20MinterAddress =
    erc20MinterAddresses[chainId as keyof typeof erc20MinterAddresses];
  if (!erc20MinterAddress)
    throw new Error(`ERC20Minter not deployed on chainId ${chainId}`);

  const erc20MinterApproval = encodeFunctionData({
    abi: zoraCreator1155ImplABI,
    functionName: "addPermission",
    args: [BigInt(nextTokenId), erc20MinterAddress, PERMISSION_BITS.MINTER],
  });

  const saleData = encodeFunctionData({
    abi: erc20MinterABI,
    functionName: "setSale",
    args: [
      BigInt(nextTokenId),
      {
        saleStart: saleStart || BigInt(0),
        saleEnd: saleEnd || BigInt(0),
        maxTokensPerAddress: BigInt(mintLimit || 0),
        pricePerToken: pricePerToken,
        fundsRecipient,
        currency: currency,
      },
    ],
  });

  const callSale = encodeFunctionData({
    abi: zoraCreator1155ImplABI,
    functionName: "callSale",
    args: [BigInt(nextTokenId), erc20MinterAddress, saleData],
  });

  return {
    minter: erc20MinterAddress,
    setupActions: [erc20MinterApproval, callSale],
  };
}

type SetupFixedPriceMinterProps = {
  fundsRecipient: Address;
  tokenId: bigint;
  chainId: number;
} & Concrete<Omit<SalesConfigParamsType, "currency">>;

function setupFixedPriceMinter({
  pricePerToken: price,
  tokenId: nextTokenId,
  chainId,
  saleStart,
  saleEnd,
  maxTokensPerAddress: mintLimit,
  fundsRecipient,
}: SetupFixedPriceMinterProps): { minter: Address; setupActions: Hex[] } {
  const fixedPriceStrategyAddress =
    zoraCreatorFixedPriceSaleStrategyAddress[
      chainId as keyof typeof zoraCreatorFixedPriceSaleStrategyAddress
    ];
  const fixedPriceApproval = encodeFunctionData({
    abi: zoraCreator1155ImplABI,
    functionName: "addPermission",
    args: [
      BigInt(nextTokenId),
      fixedPriceStrategyAddress,
      PERMISSION_BITS.MINTER,
    ],
  });

  const saleData = encodeFunctionData({
    abi: zoraCreatorFixedPriceSaleStrategyABI,
    functionName: "setSale",
    args: [
      BigInt(nextTokenId),
      {
        pricePerToken: price,
        saleStart: saleStart || BigInt(0),
        saleEnd: saleEnd || BigInt(0),
        maxTokensPerAddress: BigInt(mintLimit || 0),
        fundsRecipient,
      },
    ],
  });

  const callSale = encodeFunctionData({
    abi: zoraCreator1155ImplABI,
    functionName: "callSale",
    args: [BigInt(nextTokenId), fixedPriceStrategyAddress, saleData],
  });

  return {
    minter: fixedPriceStrategyAddress,
    setupActions: [fixedPriceApproval, callSale],
  };
}

export function setupMinters({ salesConfig, ...rest }: SetupMintersProps): {
  minter: Address;
  setupActions: Hex[];
} {
  if (!salesConfig) throw new Error("No sales config for token");
  const { currency: currencyAddress } = salesConfig;

  if (currencyAddress === zeroAddress) {
    return setupFixedPriceMinter({
      ...salesConfig,
      ...rest,
    });
  } else {
    return setupErc20Minter({
      ...salesConfig,
      ...rest,
    });
  }
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
