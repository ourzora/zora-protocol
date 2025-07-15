import { Account, Address } from "viem";
import {
  GenericTokenIdTypes,
  SimulateContractParametersWithAccount,
  WithPublicClient,
} from "src/types";
import { AllowListEntry } from "src/allow-list/types";
import { TokenQueryResult } from "./subgraph-queries";
import { IPremintGetter } from "src/premint/premint-api-client";

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

export type MintType = "1155" | "721" | "allowlist" | "premint";

export type MintTypes =
  | Erc1155MintParameters
  | Erc721MintParameters
  | PremintMintParameters;

export type GetMintParametersArguments = MintTypes & {
  /** Address of the contract that the item belongs to */
  tokenContract: Address;
  preferredSaleType?: SaleType;
};

type WithOptionalGetters<T> = T & {
  /** Optional override for getting onchain mints using indexed events */
  mintGetter?: IOnchainMintGetter;
  /** Optional override for getting premints */
  premintGetter?: IPremintGetter;
};

export type WithPublicClientAndOptionalGetters<T> = WithOptionalGetters<
  WithPublicClient<T>
>;

export type WithPublicClientAndRequiredGetters<T> = WithPublicClient<T> & {
  mintGetter: IOnchainMintGetter;
  premintGetter: IPremintGetter;
};

export type GetMintParameters =
  WithPublicClientAndOptionalGetters<GetMintParametersArguments>;

export type GetMintsOfContractParametersArguments = {
  /** Address of the contract to get the tokens of */
  tokenContract: Address;
  preferredSaleType?: SaleType;
};

export type GetMintsOfContractParameters =
  WithPublicClientAndOptionalGetters<GetMintsOfContractParametersArguments>;

export const isOnChainMint = (mint: MintTypes): mint is OnChainMintParameters =>
  mint.mintType !== "premint";

export const is1155Mint = (mint: MintTypes): mint is Erc1155MintParameters =>
  mint.mintType === "1155";

export type MintParametersBase = {
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
  /** If this is a premint, the address to get the first minter reward */
  firstMinter?: Address;
  /** If this is an allow list mint, the info for the allow list entry */
  allowListEntry?: AllowListEntry;
};

export type MakeMintParametersArgumentsBase = MintParametersBase & {
  /** Premint contract address */
  tokenContract: Address;
};

export type Make1155MintArguments = MakeMintParametersArgumentsBase &
  Erc1155MintParameters & {
    preferredSaleType?: SaleType;
  };

export type Make721MintArguments = MakeMintParametersArgumentsBase &
  Erc721MintParameters & {
    preferredSaleType?: SaleType;
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

export type MakeMintParameters =
  WithPublicClient<MakeMintParametersArguments> & {
    mintGetter?: IOnchainMintGetter;
    premintGetter?: IPremintGetter;
  };

export type GetMintCostsParameterArguments = {
  /** Address of token contract/collection to get the mint costs for */
  collection: Address;
  /** Quantity of tokens that will be minted */
  quantityMinted: number | bigint;
} & MintTypes;

export type SaleType =
  | "fixedPrice"
  | "erc20"
  | "allowlist"
  | "premint"
  | "timed";

type SaleStrategy<T extends SaleType> = {
  saleType: T;
  mintFeePerQuantity: bigint;
};

type PricedSaleStrategy = {
  pricePerToken: bigint;
  maxTokensPerAddress: bigint;
};

export type StartAndEnd = {
  saleStart: string;
  saleEnd: string;
};

type FixedPriceSaleStrategy = SaleStrategy<"fixedPrice"> &
  PricedSaleStrategy &
  StartAndEnd & {
    address: Address;
  };

type ERC20SaleStrategy = SaleStrategy<"erc20"> &
  PricedSaleStrategy &
  StartAndEnd & {
    address: Address;
    currency: Address;
  };

type AllowListSaleStrategy = SaleStrategy<"allowlist"> & {
  address: Address;
  saleStart: string;
  saleEnd: string;
  merkleRoot: string;
};

export type ZoraTimedSaleStrategy = SaleStrategy<"timed"> & {
  mintFee: bigint;
  erc20Z: Address;
  pool: Address;
  secondaryActivated: boolean;
  address: Address;
  saleStart: string;
  saleEnd?: string;
  minimumMarketEth?: bigint;
  marketCountdown?: bigint;
};

type PremintSaleStrategy = SaleStrategy<"premint"> &
  PricedSaleStrategy & {
    duration: bigint;
  };

export type OnchainSalesStrategies =
  | FixedPriceSaleStrategy
  | ERC20SaleStrategy
  | AllowListSaleStrategy
  | ZoraTimedSaleStrategy;

export type SaleStrategies = OnchainSalesStrategies | PremintSaleStrategy;

export function isErc20SaleStrategy(
  salesConfig: SaleStrategies,
): salesConfig is ERC20SaleStrategy {
  return salesConfig.saleType === "erc20";
}

export function isTimedSaleStrategy(
  salesConfig: SaleStrategies,
): salesConfig is ZoraTimedSaleStrategy {
  return salesConfig.saleType === "timed";
}

export type ContractInfo = {
  /** Address of the contract */
  address: Address;
  /** Contract metadata uri */
  URI: string;
  /** Contract name */
  name: string;
};

export type MintableBase = {
  /** The contract the mintable belongs to */
  contract: ContractInfo;
  /** Token metadata URI */
  tokenURI: string;
  /** Creator of the mintable item */
  creator: Address;
  /** Maximum total number of items that can be minted */
  maxSupply: bigint;
  /** Total number of items minted so far */
  totalMinted: bigint;
};

export type OnchainMintable = MintableBase & {
  mintType: "721" | "1155";
  tokenId?: bigint;
  contractVersion: string;
};

export type PremintMintable = MintableBase & {
  mintType: "premint";
  uid: number;
};

export type OnchainSalesConfigAndTokenInfo = {
  salesConfig?: OnchainSalesStrategies;
} & OnchainMintable;

export type PremintSalesConfigAndTokenInfo = {
  salesConfig: PremintSaleStrategy;
} & PremintMintable;

export type SalesConfigAndTokenInfo =
  | OnchainSalesConfigAndTokenInfo
  | PremintMintable;

export type GetMintableReturn = {
  salesConfigAndTokenInfo: OnchainSalesConfigAndTokenInfo;
  secondaryMarketActive: boolean;
  primaryMintActive: boolean;
  primaryMintEnd?: bigint;
};

export interface IOnchainMintGetter {
  getMintable(params: {
    tokenAddress: Address;
    tokenId?: GenericTokenIdTypes;
  }): Promise<TokenQueryResult>;

  getContractMintable(params: {
    tokenAddress: Address;
  }): Promise<GetMintableReturn[]>;

  getContractPremintTokenIds(params: {
    tokenAddress: Address;
  }): Promise<{ tokenId: BigInt; uid: number }[]>;
}

export type MintCosts = {
  /** The total of the mint fee, in eth */
  mintFee: bigint;
  /** If it is a paid or erc20 mint, the total price of the paid or erc20 mint in eth or erc20 value correspondingly. */
  totalPurchaseCost: bigint;
  /** If it is an erc20 mint, the erc20 address */
  totalPurchaseCostCurrency?: Address;
  /** The total cost in eth (mint fee + purchase cost) to mint */
  totalCostEth: bigint;
};

export type Erc20Approval = {
  /** ERC20 token address that must be approved */
  erc20: Address;
  /** Quantity of ERC20 that must be approved */
  quantity: bigint;
  /** Address that must be approved to transfer to */
  approveTo: Address;
};

export type PrepareMintReturn = {
  /** Prepared parameters to execute the mint transaction */
  parameters: SimulateContractParametersWithAccount;
  /** If an erc20 approval is necessary, information for the erc20 approval */
  erc20Approval?: Erc20Approval;
  /** Cost breakdown to mint the quantity of tokens */
  costs: MintCosts;
};

export type PrepareMint = (params: MintParametersBase) => PrepareMintReturn;
export type AsyncPrepareMint = (
  params: MintParametersBase,
) => Promise<PrepareMintReturn>;

export type MintableReturn = {
  /** Token information */
  token: SalesConfigAndTokenInfo;
  /** If the primary mint is active, the end time of the primary mint, if there is an end time */
  primaryMintEnd?: bigint;
  secondaryMarketActive: boolean;
} & (
  | {
      primaryMintActive: true;
      /** Function that takes a quantity of items to mint and returns a prepared transaction and the costs to mint that quantity.  If the primary mint is not active, it will be undefined. */
      prepareMint: PrepareMint;
    }
  | {
      primaryMintActive: false;
      prepareMint?: undefined;
    }
);
