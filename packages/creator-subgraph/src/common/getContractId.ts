import { Address } from "@graphprotocol/graph-ts"

export function getContractId(contractAddress: Address): string {
  return contractAddress.toHex();
}