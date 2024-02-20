import { Address, BigInt } from "@graphprotocol/graph-ts";

export const getPermissionsKey = (
  user: Address,
  address: Address,
  tokenId: BigInt
): string => `${user.toHex()}-${address.toHex()}-${tokenId.toString()}`;
