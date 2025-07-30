import { ethereum } from "@graphprotocol/graph-ts";

export const getOnChainMetadataKey = (event: ethereum.Event): string =>
  `${event.transaction.hash.toHex()}-${event.logIndex.toString()}`;
