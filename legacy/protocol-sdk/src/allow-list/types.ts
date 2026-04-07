import { Address, Hex } from "viem";

export type AllowList = {
  entries: {
    user: Address;
    price: bigint;
    maxCanMint: number;
  }[];
};

export type AllowListEntry = {
  maxCanMint: number;
  price: bigint;
  proof: Hex[];
};
