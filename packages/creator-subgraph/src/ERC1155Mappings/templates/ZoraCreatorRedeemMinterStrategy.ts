import { BigInt } from "@graphprotocol/graph-ts";
import {
  RedeemInstructions,
  RedeemMinterProcessed,
  RedeemMintToken,
  RedeemProcessedTokenPair,
  SalesConfigRedeemMinterStrategy,
  SalesStrategyConfig,
} from "../../../generated/schema";
import {
  RedeemProcessed,
  RedeemsCleared,
  RedeemSet,
} from "../../../generated/templates/ZoraCreatorRedeemMinterStrategy/ZoraCreatorRedeemMinterStrategy";
import { getTokenId } from "../../common/getTokenId";
import { makeTransaction } from "../../common/makeTransaction";
import { SALE_CONFIG_REDEEM_STRATEGY } from "../../constants/salesConfigTypes";
import { getContractId } from "../../common/getContractId";

export function handleRedeemCleared(event: RedeemsCleared): void {
  for (let i = 0; i < event.params.redeemInstructionsHashes.length; i++) {
    const redeem = SalesConfigRedeemMinterStrategy.load(
      `${event.params.redeemInstructionsHashes[i]}`
    );

    if (redeem) {
      redeem.isActive = false;
      redeem.save();
    }
  }
}

export function handleRedeemProcessed(event: RedeemProcessed): void {
  const id = `${event.transaction.hash.toHex()}`;
  const processed = new RedeemMinterProcessed(id);

  const txn = makeTransaction(event);
  processed.txn = txn;
  processed.block = event.block.number;
  processed.timestamp = event.block.timestamp;
  processed.address = event.address;

  processed.redeemMinter = event.params.redeemsInstructionsHash.toHex();
  processed.target = event.params.target;
  processed.redeemsInstructionsHash = event.params.redeemsInstructionsHash;
  processed.sender = event.params.sender;

  for (let i = 0; i < event.params.amounts.length; i++) {
    const pair = new RedeemProcessedTokenPair(`${id}-redeemed-${i}`);
    pair.processed = id;
    pair.index = i;
    pair.amounts = event.params.amounts[i];
    pair.tokenIds = event.params.tokenIds[i];
    pair.save();
  }

  processed.save();
}

export function handleRedeemSet(event: RedeemSet): void {
  const transactionHash = event.transaction.hash.toHex();
  const redemptionHash = event.params.redeemsInstructionsHash.toHex();
  const txn = makeTransaction(event);

  let token = RedeemMintToken.load(redemptionHash);
  if (token === null) {
    token = new RedeemMintToken(redemptionHash);
  }

  token.tokenContract = event.params.data.mintToken.tokenContract;
  token.tokenId = event.params.data.mintToken.tokenId;
  token.amount = event.params.data.mintToken.amount;
  token.tokenType = event.params.data.mintToken.tokenType;
  token.save();

  let strategy = SalesConfigRedeemMinterStrategy.load(redemptionHash);
  if (strategy === null) {
    strategy = new SalesConfigRedeemMinterStrategy(redemptionHash);
  }

  strategy.txn = txn;
  strategy.block = event.block.number;
  strategy.timestamp = event.block.timestamp;
  strategy.address = event.address;
  strategy.configAddress = event.address;
  strategy.target = event.params.target;
  strategy.redeemsInstructionsHash = event.params.redeemsInstructionsHash;
  strategy.saleStart = event.params.data.saleStart;
  strategy.saleEnd = event.params.data.saleEnd;
  strategy.ethAmount = event.params.data.ethAmount;
  strategy.ethRecipient = event.params.data.ethRecipient;
  strategy.isActive = true;
  strategy.redeemMintToken = token.id;
  strategy.save();

  for (let i = 0; i < event.params.data.instructions.length; i++) {
    // This can fail for duplicate Redeem Instructions – while it doesn't make sense that the user can input this
    // the safest way to index these is by array index. Transaction hash added for uniqueness.
    const id = `${redemptionHash}-${i}-${transactionHash}`
    
    let redeemInstruction = RedeemInstructions.load(id);
    if (redeemInstruction === null) {
      redeemInstruction = new RedeemInstructions(id);
    }

    redeemInstruction.tokenType = event.params.data.instructions[i].tokenType;
    redeemInstruction.amount = event.params.data.instructions[i].amount;
    redeemInstruction.tokenIdStart =
      event.params.data.instructions[i].tokenIdStart;
    redeemInstruction.tokenIdEnd = event.params.data.instructions[i].tokenIdEnd;
    redeemInstruction.transferRecipient =
      event.params.data.instructions[i].transferRecipient;
    redeemInstruction.tokenContract =
      event.params.data.instructions[i].tokenContract;
    redeemInstruction.burnFunction =
      event.params.data.instructions[i].burnFunction;
    redeemInstruction.redeemMinter = strategy.id;
    redeemInstruction.save();
  }

  // add join
  let saleJoin = SalesStrategyConfig.load(redemptionHash);
  if (saleJoin === null) {
    saleJoin = new SalesStrategyConfig(redemptionHash);
  }

  if (event.params.data.mintToken.tokenId.equals(BigInt.zero())) {
    saleJoin.contract = getContractId(event.params.data.mintToken.tokenContract);
  } else {
    saleJoin.tokenAndContract = getTokenId(
      event.params.data.mintToken.tokenContract,
      event.params.data.mintToken.tokenId
    );
  }
  saleJoin.block = event.block.number;
  saleJoin.address = event.address;
  saleJoin.timestamp = event.block.timestamp;
  saleJoin.redeemMinter = strategy.id;
  saleJoin.type = SALE_CONFIG_REDEEM_STRATEGY;
  saleJoin.txn = txn;
  saleJoin.save();
}
