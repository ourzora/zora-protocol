import { Account, Address } from "viem";
import { GenericTokenIdTypes } from "src/types";

export type MintParameters<MintType> = {
  /** Type of the collection to be minted. */
  mintType: MintType;
};

export type Erc1155MintParameters = MintParameters<"1155"> & {
  /** Token id to mint */
  tokenId: GenericTokenIdTypes;
};

export type Erc721MintParameters = MintParameters<"721">;

export type OnChainMintParameters =
  | Erc1155MintParameters
  | Erc721MintParameters;

export type PremintMintParameters = MintParameters<"premint"> & {
  /** uid of the Premint to mint */
  uid: number;
};

export type MintType = "1155" | "721" | "premint";

export type MintTypes =
  | Erc1155MintParameters
  | Erc721MintParameters
  | PremintMintParameters;

export const isOnChainMint = (mint: MintTypes): mint is OnChainMintParameters =>
  mint.mintType !== "premint";

export const is1155Mint = (mint: MintTypes): mint is Erc1155MintParameters =>
  mint.mintType === "1155";

export type MakeMintParametersArgumentsBase = {
  /** Premint contract address */
  tokenContract: Address;
  /** Account to execute the mint */
  minterAccount: Account | Address;
  /** Quantity of tokens to mint. Defaults to 1 */
  quantityToMint: number | bigint;
  /** Comment to add to the mint */
  mintComment?: string;
  /** Address to receive the mint referral reward */
  mintReferral?: Address;
  /** Address to receive the minted tokens. Defaults to the minting account */
  mintRecipient?: Address;
};

export type Make1155MintArguments = MakeMintParametersArgumentsBase &
  Erc1155MintParameters & {
    saleType?: SaleType;
  };

export type Make721MintArguments = MakeMintParametersArgumentsBase &
  Erc721MintParameters & {
    saleType?: SaleType;
  };

export type MakePremintMintParametersArguments =
  MakeMintParametersArgumentsBase &
    PremintMintParameters & {
      /** Account to receive first minter reward, if this mint brings the premint onchain */
      firstMinter?: Address;
    };

export type MakeMintParametersArguments =
  | Make1155MintArguments
  | Make721MintArguments
  | MakePremintMintParametersArguments;

export type GetMintCostsParameters = {
  /** Address of token contract/collection to get the mint costs for */
  collection: Address;
  /** Quantity of tokens that will be minted */
  quantityMinted: number | bigint;
} & MintTypes;

export type SaleType = "fixedPrice" | "erc20";

type SaleStrategy<T extends SaleType> = {
  saleType: T;
  address: Address;
  pricePerToken: bigint;
  saleEnd: string;
  saleStart: string;
  maxTokensPerAddress: bigint;
};

type FixedPriceSaleStrategy = SaleStrategy<"fixedPrice">;

type ERC20SaleStrategy = SaleStrategy<"erc20"> & {
  currency: Address;
};

type SaleStrategies = FixedPriceSaleStrategy | ERC20SaleStrategy;

export function isErc20SaleStrategy(
  salesConfig: SaleStrategies,
): salesConfig is ERC20SaleStrategy {
  return salesConfig.saleType === "erc20";
}

export type SalesConfigAndTokenInfo = {
  salesConfig: SaleStrategies;
  mintFeePerQuantity: bigint;
};

export interface IMintGetter {
  getSalesConfigAndTokenInfo({
    tokenAddress,
    tokenId,
    saleType,
  }: {
    tokenAddress: Address;
    tokenId?: GenericTokenIdTypes;
    saleType?: SaleType;
  }): Promise<SalesConfigAndTokenInfo>;
}
