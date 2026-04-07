import { SetupNewCointag } from "../../generated/CointagFactory/CointagFactory";
import { Cointag as CointagContract } from "../../generated/CointagFactory/Cointag";
import { Cointag } from "../../generated/schema";
import { BigInt } from "@graphprotocol/graph-ts";
import { makeTransaction } from "../common/makeTransaction";

export function handleSetupNewCointag(event: SetupNewCointag): void {
  const cointagId = event.params.cointag.toHexString();

  let cointag = new Cointag(cointagId);

  cointag.txn = makeTransaction(event);
  cointag.timestamp = event.block.timestamp;
  cointag.block = event.block.number;

  cointag.creatorRewardRecipient = event.params.creatorRewardRecipient;
  cointag.pool = event.params.pool;
  cointag.percentageToBuyBurn = event.params.percentageToBuyBurn;

  cointag.erc20 = event.params.erc20;

  const cointagContract = CointagContract.bind(event.params.cointag);
  cointag.version = cointagContract.contractVersion();

  cointag.createdOn = event.block.timestamp;
  cointag.protocolRewardsBalance = BigInt.fromI32(0);

  cointag.save();
}
