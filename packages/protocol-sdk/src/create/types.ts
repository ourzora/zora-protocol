import { AsyncPrepareMint } from "src/mint/types";
import { Concrete } from "src/utils";
import { Account, Address, Hex, SimulateContractParameters } from "viem";

export type NewContractParams = {
  name: string;
  uri: string;
  defaultAdmin?: Address;
};

export type SaleStartAndEnd = {
  // defaults to 0, in seconds
  saleStart?: bigint;
  // defaults to forever, in seconds
  saleEnd?: bigint;
};

export type MaxTokensPerAddress = {
  // max tokens that can be minted per address
  maxTokensPerAddress?: bigint;
};

export type FixedPriceParamsType = SaleStartAndEnd &
  MaxTokensPerAddress & {
    type?: "fixedPrice";
    // the price per token, if it is a priced mint
    pricePerToken: bigint;
  };

export type TimedSaleParamsType = SaleStartAndEnd & {
  type?: "timed";
  // Name of the erc20z token to create for the secondary sale.  If not provided, uses the contract name
  erc20Name?: string;
  // Symbol of the erc20z token to create for the secondary sale.  If not provided, extracts it from the name.
  erc20Symbol?: string;
};

export type Erc20ParamsType = SaleStartAndEnd &
  MaxTokensPerAddress & {
    type: "erc20Mint";
    // if the erc20 address of the token to mint against
    currency: Address;
    // price in currency per token
    pricePerToken: bigint;
  };

export type AllowListParamType = SaleStartAndEnd & {
  type: "allowlistMint";
  // the merkle root of the allowlist
  presaleMerkleRoot: `0x${string}`;
};

export type SalesConfigParamsType =
  | AllowListParamType
  | Erc20ParamsType
  | FixedPriceParamsType
  | TimedSaleParamsType;

export type CreateNew1155ParamsBase = {
  account: Address;
  getAdditionalSetupActions?: (args: { tokenId: bigint }) => Hex[];
  token: CreateNew1155TokenProps;
};

export type CreateNew1155ContractParams = CreateNew1155ParamsBase & {
  contract: NewContractParams;
};

export type CreateNew1155TokenParams = CreateNew1155ParamsBase & {
  contractAddress: Address;
};

export type AllowlistData = {
  saleStart?: bigint;
  saleEnd?: bigint;
  presaleMerkleRoot: `0x${string}`;
};

export type CreateNew1155TokenProps = {
  maxSupply?: bigint | number;
  tokenMetadataURI: string;
  royaltyBPS?: number;
  createReferral?: Address;
  mintToCreatorCount?: number;
  payoutRecipient?: Address;
  salesConfig?: SalesConfigParamsType;
};

export interface ContractProps {
  nextTokenId: bigint;
  contractVersion: string;
}

export type ConcreteSalesConfig =
  | Concrete<FixedPriceParamsType>
  | Concrete<Erc20ParamsType>
  | Concrete<AllowListParamType>
  | Concrete<TimedSaleParamsType>;

export type New1155Token = {
  payoutRecipient: Address;
  createReferral: Address;
  maxSupply: bigint;
  royaltyBPS: number;
  tokenMetadataURI: string;
  salesConfig: ConcreteSalesConfig;
};

export type CreateNew1155TokenReturn = {
  parameters: SimulateContractParameters<
    any,
    any,
    any,
    any,
    any,
    Account | Address
  >;
  tokenSetupActions: Hex[];
  newTokenId: bigint;
  newToken: New1155Token;
  minter: Address;
  contractVersion: string;
  prepareMint: AsyncPrepareMint;
};

export type CreateNew1155ContractAndTokenReturn = {
  contractAddress: Address;
} & CreateNew1155TokenReturn;
