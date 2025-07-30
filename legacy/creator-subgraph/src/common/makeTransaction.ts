import { BigInt, ethereum } from "@graphprotocol/graph-ts";
import { TransactionInfo } from "../../generated/schema";
import { chainid, network } from "../constants/chainid";

export function makeTransaction(event: ethereum.Event): string {
  const txn = new TransactionInfo(event.transaction.hash.toHex());

  txn.block = event.block.number;
  txn.timestamp = event.block.timestamp;
  txn.logIndex = event.logIndex;
  txn.chainId = chainid;
  txn.address = event.address;
  txn.network = network;
  txn.save();

  return txn.id;
}
