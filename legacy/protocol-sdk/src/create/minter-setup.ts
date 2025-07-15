import {
  erc20MinterABI,
  erc20MinterAddress as erc20MinterAddresses,
  zoraCreator1155ImplABI,
  zoraCreatorFixedPriceSaleStrategyABI,
  zoraCreatorFixedPriceSaleStrategyAddress,
  zoraCreatorMerkleMinterStrategyABI,
  zoraCreatorMerkleMinterStrategyAddress,
  zoraTimedSaleStrategyABI,
  zoraTimedSaleStrategyAddress,
} from "@zoralabs/protocol-deployments";
import { Address, encodeFunctionData, Hex } from "viem";
import {
  AllowlistData,
  ConcreteSalesConfig,
  AllowListParamType,
  Erc20ParamsType,
  FixedPriceParamsType,
  TimedSaleParamsType,
} from "./types";
import { Concrete } from "src/utils";

const PERMISSION_BITS = {
  MINTER: 2n ** 2n,
};

type SetupErc20MinterProps = {
  chainId: number;
  tokenId: bigint;
  fundsRecipient: Address;
} & Concrete<Erc20ParamsType>;

type SetupMintersProps = {
  tokenId: bigint;
  chainId: number;
  fundsRecipient: Address;
  salesConfig: ConcreteSalesConfig;
};

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
} & Concrete<FixedPriceParamsType>;

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

type SetupTimedMinterProps = {
  tokenId: bigint;
  chainId: number;
} & Concrete<TimedSaleParamsType>;

function setupTimedSaleMinter({
  chainId,
  tokenId,
  erc20Name: erc20zName,
  erc20Symbol: erc20zSymbol,
  saleStart,
  marketCountdown,
  minimumMarketEth,
}: SetupTimedMinterProps): {
  minter: Address;
  setupActions: Hex[];
} {
  const minterAddress =
    zoraTimedSaleStrategyAddress[
      chainId as keyof typeof zoraTimedSaleStrategyAddress
    ];
  const minterApproval = encodeFunctionData({
    abi: zoraCreator1155ImplABI,
    functionName: "addPermission",
    args: [BigInt(tokenId), minterAddress, PERMISSION_BITS.MINTER],
  });

  const saleData = encodeFunctionData({
    abi: zoraTimedSaleStrategyABI,
    functionName: "setSaleV2",
    args: [
      BigInt(tokenId),
      {
        saleStart,
        marketCountdown,
        minimumMarketEth,
        name: erc20zName,
        symbol: erc20zSymbol,
      },
    ],
  });

  const callSale = encodeFunctionData({
    abi: zoraCreator1155ImplABI,
    functionName: "callSale",
    args: [BigInt(tokenId), minterAddress, saleData],
  });

  return {
    minter: minterAddress,
    setupActions: [minterApproval, callSale],
  };
}

function setupAllowListMinter({
  chainId,
  tokenId: nextTokenId,
  allowlist,
  fundsRecipient,
}: {
  chainId: number;
  tokenId: bigint;
  allowlist: Concrete<AllowlistData>;
  fundsRecipient: Address;
}) {
  const merkleSaleStrategyAddress =
    zoraCreatorMerkleMinterStrategyAddress[
      chainId as keyof typeof zoraCreatorMerkleMinterStrategyAddress
    ];

  const merkleApproval = encodeFunctionData({
    abi: zoraCreator1155ImplABI,
    functionName: "addPermission",
    args: [nextTokenId, merkleSaleStrategyAddress, PERMISSION_BITS.MINTER],
  });

  const merkleRoot = allowlist.presaleMerkleRoot.startsWith("0x")
    ? allowlist.presaleMerkleRoot
    : (`0x${allowlist.presaleMerkleRoot}` as Hex);

  const saleData = encodeFunctionData({
    abi: zoraCreatorMerkleMinterStrategyABI,
    functionName: "setSale",
    args: [
      BigInt(nextTokenId),
      {
        presaleStart: allowlist.saleStart,
        presaleEnd: allowlist.saleEnd,
        merkleRoot,
        fundsRecipient: fundsRecipient,
      },
    ],
  });

  const callSaleMerkle = encodeFunctionData({
    abi: zoraCreator1155ImplABI,
    functionName: "callSale",
    args: [BigInt(nextTokenId), merkleSaleStrategyAddress, saleData],
  });

  return {
    minter: merkleSaleStrategyAddress,
    setupActions: [merkleApproval, callSaleMerkle],
  };
}

const isAllowList = (
  salesConfig: ConcreteSalesConfig,
): salesConfig is Concrete<AllowListParamType> =>
  salesConfig.type === "allowlistMint";
const isErc20 = (
  salesConfig: ConcreteSalesConfig,
): salesConfig is Concrete<Erc20ParamsType> => salesConfig.type === "erc20Mint";
const isFixedPrice = (
  salesConfig: ConcreteSalesConfig,
): salesConfig is Concrete<FixedPriceParamsType> =>
  salesConfig.type === "fixedPrice" ||
  (salesConfig as unknown as Concrete<FixedPriceParamsType>).pricePerToken >
    BigInt(0);

export function setupMinters({ salesConfig, ...rest }: SetupMintersProps): {
  minter: Address;
  setupActions: Hex[];
} {
  if (isErc20(salesConfig)) {
    return setupErc20Minter({
      ...salesConfig,
      ...rest,
    });
  }
  if (isAllowList(salesConfig)) {
    return setupAllowListMinter({
      allowlist: salesConfig,
      ...rest,
    });
  }

  if (isFixedPrice(salesConfig))
    return setupFixedPriceMinter({
      ...salesConfig,
      ...rest,
    });

  return setupTimedSaleMinter({
    ...salesConfig,
    ...rest,
  });
}
