import { Address, BigInt } from "@graphprotocol/graph-ts";
import {
  TransferSingle,
  TransferBatch,
  TokenCreated,
} from "../../generated/ZoraSparks/ZoraSparks1155";

import { SparkAccountBalance, SparkToken } from "../../generated/schema";

const zeroAddress = "0x0000000000000000000000000000000000000000";

export function handleTokenCreated(event: TokenCreated): void {
  const createdSparkToken = new SparkToken(`${event.params.tokenId}`);
  createdSparkToken.tokenId = event.params.tokenId;
  createdSparkToken.pricePerToken = event.params.price;
  createdSparkToken.tokenAddress = event.params.tokenAddress;

  createdSparkToken.save();
}

export function incrementRecipientBalance(
  toAddress: Address,
  value: BigInt,
  tokenId: BigInt,
): void {
  if (toAddress.toHex() != zeroAddress) {
    var sparkAccountBalanceTo = SparkAccountBalance.load(
      `${toAddress.toHexString()}-${tokenId}`,
    );
    if (sparkAccountBalanceTo == null) {
      sparkAccountBalanceTo = new SparkAccountBalance(
        `${toAddress.toHexString()}-${tokenId}`,
      );
      sparkAccountBalanceTo.balance = BigInt.fromI32(0);
      sparkAccountBalanceTo.account = toAddress;
      sparkAccountBalanceTo.sparkToken = `${tokenId}`;
    }

    sparkAccountBalanceTo.balance = sparkAccountBalanceTo.balance.plus(value);
    sparkAccountBalanceTo.save();
  }
}

export function deductFromSenderBalance(
  fromAddress: Address,
  value: BigInt,
  tokenId: BigInt,
): void {
  if (fromAddress.toHex() != zeroAddress) {
    var sparkAccountBalanceFrom = SparkAccountBalance.load(
      `${fromAddress.toHexString()}-${tokenId}`,
    );
    if (sparkAccountBalanceFrom == null) {
      sparkAccountBalanceFrom = new SparkAccountBalance(
        `${fromAddress.toHexString()}-${tokenId}`,
      );
      sparkAccountBalanceFrom.balance = BigInt.fromI32(0);
      sparkAccountBalanceFrom.account = fromAddress;
      sparkAccountBalanceFrom.sparkToken = `${tokenId}`;
    }

    sparkAccountBalanceFrom.balance =
      sparkAccountBalanceFrom.balance.minus(value);
    sparkAccountBalanceFrom.save();
  }
}

export function handleTransferSingle(event: TransferSingle): void {
  const sparkToken = new SparkToken(`${event.params.id.toHexString()}`);

  if (sparkToken == null || event.params.value.equals(BigInt.fromI32(0))) {
    return;
  }

  // recipient balance
  incrementRecipientBalance(
    event.params.to,
    event.params.value,
    event.params.id,
  );

  // sender balance
  deductFromSenderBalance(
    event.params.from,
    event.params.value,
    event.params.id,
  );
}

export function handleTransferBatch(event: TransferBatch): void {
  for (let i = 0; i < event.params.ids.length; i++) {
    const sparkToken = new SparkToken(`${event.params.ids[i].toHexString()}`);

    if (
      sparkToken == null ||
      event.params.values[i].equals(BigInt.fromI32(0))
    ) {
      continue;
    }

    // recipient balance
    incrementRecipientBalance(
      event.params.to,
      event.params.values[i],
      event.params.ids[i],
    );

    // sender balance
    deductFromSenderBalance(
      event.params.from,
      event.params.values[i],
      event.params.ids[i],
    );
  }
}
