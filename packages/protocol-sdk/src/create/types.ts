import { Concrete } from "src/utils";
import { Address, Hex } from "viem";

export type ContractType =
  | {
      name: string;
      uri: string;
      defaultAdmin?: Address;
    }
  | Address;

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

export type CreateNew1155Params = {
  account: Address;
  contract: ContractType;
  getAdditionalSetupActions?: (args: {
    tokenId: bigint;
    contractAddress: Address;
  }) => Hex[];
  token: CreateNew1155TokenProps;
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
