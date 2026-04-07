import { ethereum } from "@graphprotocol/graph-ts";

export function getMintCommentId(event: ethereum.Event): string {
  return `${event.transaction.hash.toHex()}-${event.logIndex}`;
}
