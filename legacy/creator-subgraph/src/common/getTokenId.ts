import { Address, BigInt } from "@graphprotocol/graph-ts";

export const getTokenId = (contract: Address, tokenId: BigInt): string =>
  `${contract.toHexString()}-${tokenId.toString()}`;

export const getDefaultTokenId = (contract: Address): string =>
  getTokenId(contract, BigInt.zero());
