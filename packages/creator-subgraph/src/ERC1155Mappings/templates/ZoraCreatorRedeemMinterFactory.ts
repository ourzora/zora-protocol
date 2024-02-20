import { RedeemMinterDeployed } from "../../../generated/templates/ZoraCreatorRedeemMinterFactory/ZoraCreatorRedeemMinterFactory";
import { ZoraCreatorRedeemConfig } from "../../../generated/schema";
import { makeTransaction } from "../../common/makeTransaction";
import { ZoraCreatorRedeemMinterStrategy } from "../../../generated/templates";

export function handleRedeemMinterDeployed(event: RedeemMinterDeployed): void {
  let config = new ZoraCreatorRedeemConfig(
    `${event.address.toHex()}-${event.params.minterContract.toHex()}`
  );
  config.creatorAddress = event.params.creatorContract;
  config.minterAddress = event.params.minterContract;

  const txn = makeTransaction(event);
  config.txn = txn;
  config.block = event.block.number;
  config.timestamp = event.block.timestamp;

  ZoraCreatorRedeemMinterStrategy.create(event.params.minterContract);

  config.save();
}
