import { BigInt } from "@graphprotocol/graph-ts";

export function hasBit(bit: u8, permissions: BigInt): boolean {
  return permissions.bitAnd(BigInt.fromI64(2).pow(bit)).gt(BigInt.fromI64(0));
}