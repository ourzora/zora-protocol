import { Address, BigInt } from "@graphprotocol/graph-ts";

export const getSalesConfigKey = (
  marketAddress: Address,
  mediaContractAddress: Address,
  tokenId: BigInt
): string =>
  `${marketAddress.toHexString()}-${mediaContractAddress.toHexString()}-${tokenId.toString()}`

export const getSalesConfigOnLegacyMarket = (
  marketAddress: Address,
  postfix: string
): string =>
  `${getSalesConfigKey(
    marketAddress,
    marketAddress,
    BigInt.zero() 
  )}-${postfix}`;
