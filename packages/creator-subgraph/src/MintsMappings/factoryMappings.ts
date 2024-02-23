import { BigInt } from "@graphprotocol/graph-ts";
import {
  EthTokenCreated,
  EthMintableTokenSet,
  Redeemed,
  TransferSingle,
  ZoraMintsImpl,
} from "../../generated/ZoraMints/ZoraMintsImpl";

import { MintAccountBalance, MintToken } from "../../generated/schema";

export function handleEthTokenCreated(event: EthTokenCreated): void {
  const createdMintToken = new MintToken(`${event.params.tokenId}`);
  createdMintToken.tokenId = event.params.tokenId;
  createdMintToken.pricePerToken = event.params.pricePerToken;
  createdMintToken.isMintable = false;

  createdMintToken.save();
}

const zeroAddress = "0x0000000000000000000000000000000000000000";

export function handleEthMintableTokenSet(event: EthMintableTokenSet): void {
  // set current active token to inactive
  const MintContract = ZoraMintsImpl.bind(event.address);
  const activeTokenId = MintContract.mintableEthToken();
  const activeMintToken = MintToken.load(`${activeTokenId}`);
  if (activeMintToken != null) {
    activeMintToken.isMintable = false;
    activeMintToken.save();
  }

  // set new token to active
  const newMintToken = MintToken.load(`${event.params.tokenId}`);
  if (newMintToken == null) {
    return;
  }

  newMintToken.isMintable = true;
  newMintToken.save();
}

export function handleTransferSingle(event: TransferSingle): void {
  const mintToken = new MintToken(`${event.params.id.toHexString()}`);

  if (mintToken == null || event.params.value.equals(BigInt.fromI32(0))) {
    return;
  }

  // recipient balance
  if (event.params.to.toHex() != zeroAddress) {
    var mintAccountBalanceTo = MintAccountBalance.load(
      `${event.params.to.toHexString()}-${event.params.id}`,
    );
    if (mintAccountBalanceTo == null) {
      mintAccountBalanceTo = new MintAccountBalance(
        `${event.params.to.toHexString()}-${event.params.id}`,
      );
      mintAccountBalanceTo.balance = BigInt.fromI32(0);
      mintAccountBalanceTo.account = event.params.to;
      mintAccountBalanceTo.mintToken = `${event.params.id}`;
    }

    mintAccountBalanceTo.balance = mintAccountBalanceTo.balance.plus(
      event.params.value,
    );
    mintAccountBalanceTo.save();
  }

  // sender balance
  if (event.params.from.toHex() != zeroAddress) {
    var mintAccountBalanceFrom = MintAccountBalance.load(
      `${event.params.from.toHexString()}-${event.params.id}`,
    );
    if (mintAccountBalanceFrom == null) {
      mintAccountBalanceFrom = new MintAccountBalance(
        `${event.params.from.toHexString()}-${event.params.id}`,
      );
      mintAccountBalanceFrom.balance = BigInt.fromI32(0);
      mintAccountBalanceFrom.account = event.params.from;
      mintAccountBalanceFrom.mintToken = `${event.params.id}`;
    }

    mintAccountBalanceFrom.balance = mintAccountBalanceFrom.balance.minus(
      event.params.value,
    );
    mintAccountBalanceFrom.save();
  }
}
