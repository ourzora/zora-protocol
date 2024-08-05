import { Concrete } from "src/utils";
import { Account, Address, Hex, SimulateContractParameters } from "viem";

export type NewContractParams = {
  name: string;
  uri: string;
  defaultAdmin?: Address;
};

export type SalesConfigParamsType = {
  // defaults to 0
  pricePerToken?: bigint;
  // defaults to 0, in seconds
  saleStart?: bigint;
  // defaults to forever, in seconds
  saleEnd?: bigint;
  // max tokens that can be minted per address
  maxTokensPerAddress?: bigint;
  // if an erc20 mint, the erc20 address.  Leave null for eth mints
  currency?: Address;
};

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

export interface CreateNew1155TokenProps {
  maxSupply?: bigint | number;
  tokenMetadataURI: string;
  royaltyBPS?: number;
  salesConfig?: SalesConfigParamsType;
  createReferral?: Address;
  mintToCreatorCount?: number;
  payoutRecipient?: Address;
}

export interface ContractProps {
  nextTokenId: bigint;
  contractVersion: string;
}

export type New1155Token = {
  payoutRecipient: Address;
  createReferral: Address;
  maxSupply: bigint;
  royaltyBPS: number;
  salesConfig: Concrete<SalesConfigParamsType>;
  tokenMetadataURI: string;
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
};

export type CreateNew1155ContractAndTokenReturn = {
  contractAddress: Address;
} & CreateNew1155TokenReturn;
