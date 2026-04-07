import { ethereum } from "@graphprotocol/graph-ts";

export function getSaleId(event: ethereum.Event): string {
  return `${event.transaction.hash.toHex()}-${event.logIndex}`;
}
