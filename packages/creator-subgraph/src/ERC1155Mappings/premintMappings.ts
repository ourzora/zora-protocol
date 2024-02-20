import { Premint } from "../../generated/schema";
import { Preminted, PremintedV2 } from "../../generated/ZoraCreator1155PremintExecutorV1/ZoraCreator1155PremintExecutorImpl";
import { getTokenId } from "../common/getTokenId";

export function handlePreminted(event: Preminted): void {
  const premint = new Premint(
    `${event.params.contractAddress.toHex()}-${event.params.tokenId.toHex()}-${event.params.minter.toHex()}}`
  );
  premint.uid = event.params.uid;
  premint.contractAddress = event.params.contractAddress;
  premint.tokenId = event.params.tokenId;
  premint.minter = event.params.minter;
  premint.tokenAndContract = getTokenId(
    event.params.contractAddress,
    event.params.tokenId
  );
  premint.createdNewContract = event.params.createdNewContract;
  premint.quantityMinted = event.params.quantityMinted;

  premint.save();
}

export function handlePremintedV2(event: PremintedV2): void {
  const premint = new Premint(
    `${event.params.contractAddress.toHex()}-${event.params.tokenId.toHex()}-${event.params.minter.toHex()}}`
  );
  premint.uid = event.params.uid;
  premint.contractAddress = event.params.contractAddress;
  premint.tokenId = event.params.tokenId;
  premint.minter = event.params.minter;
  premint.tokenAndContract = getTokenId(
    event.params.contractAddress,
    event.params.tokenId
  );
  premint.createdNewContract = event.params.createdNewContract;
  premint.quantityMinted = event.params.quantityMinted;

  premint.save();
}
