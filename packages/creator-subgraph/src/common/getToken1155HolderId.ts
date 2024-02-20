import {Address, BigInt} from '@graphprotocol/graph-ts'

export function getToken1155HolderId(user: Address, tokenContract: Address, tokenId: BigInt): string {
  return `${user.toHex()}-${tokenContract.toHex()}-${tokenId.toString()}`
}