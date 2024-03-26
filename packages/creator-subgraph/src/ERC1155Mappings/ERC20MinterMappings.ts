import {
  MintComment as ERC20MintComment,
  SaleSet,
  ERC20RewardsDeposit as ERC20RewardsDepositEvent,
} from "../../generated/ERC20Minter/ERC20Minter";
import { BigInt } from "@graphprotocol/graph-ts";
import { getSalesConfigKey } from "../common/getSalesConfigKey";
import { getTokenId } from "../common/getTokenId";
import { makeTransaction } from "../common/makeTransaction";
import { SALE_CONFIG_ERC_20_MINTER } from "../constants/salesConfigTypes";
import { getContractId } from "../common/getContractId";
import {
  SalesConfigERC20Minter,
  SalesStrategyConfig,
  MintComment,
  ERC20RewardsDeposit,
} from "../../generated/schema";
import { getMintCommentId } from "../common/getMintCommentId";

export function handleERC20MinterSaleSet(event: SaleSet): void {
  const id = getSalesConfigKey(
    event.address,
    event.params.mediaContract,
    event.params.tokenId,
  );
  let sale = new SalesConfigERC20Minter(id);
  sale.configAddress = event.address;
  sale.saleStart = event.params.salesConfig.saleStart;
  sale.contract = getContractId(event.params.mediaContract);
  sale.fundsRecipient = event.params.salesConfig.fundsRecipient;
  sale.pricePerToken = event.params.salesConfig.pricePerToken;
  sale.saleEnd = event.params.salesConfig.saleEnd;
  sale.maxTokensPerAddress = event.params.salesConfig.maxTokensPerAddress;
  sale.currency = event.params.salesConfig.currency;
  sale.tokenId = event.params.tokenId;
  const txn = makeTransaction(event);
  sale.txn = txn;
  sale.block = event.block.number;
  sale.timestamp = event.block.timestamp;
  sale.address = event.address;

  sale.save();

  const saleJoin = new SalesStrategyConfig(id);
  if (event.params.tokenId.equals(BigInt.zero())) {
    saleJoin.contract = getContractId(event.params.mediaContract);
  } else {
    saleJoin.tokenAndContract = getTokenId(
      event.params.mediaContract,
      event.params.tokenId,
    );
  }
  saleJoin.erc20Minter = id;
  saleJoin.type = SALE_CONFIG_ERC_20_MINTER;
  saleJoin.txn = txn;
  saleJoin.block = event.block.number;
  saleJoin.timestamp = event.block.timestamp;
  saleJoin.address = event.address;
  saleJoin.save();
}

export function handleMintComment(event: ERC20MintComment): void {
  const mintComment = new MintComment(getMintCommentId(event));
  const tokenAndContract = getTokenId(
    event.params.tokenContract,
    event.params.tokenId,
  );
  mintComment.tokenAndContract = tokenAndContract;
  mintComment.sender = event.params.sender;
  mintComment.comment = event.params.comment;
  mintComment.mintQuantity = event.params.quantity;
  mintComment.tokenId = event.params.tokenId;

  mintComment.txn = makeTransaction(event);
  mintComment.block = event.block.number;
  mintComment.timestamp = event.block.timestamp;
  mintComment.address = event.address;

  mintComment.save();
}

export function handleERC20RewardsDeposit(
  event: ERC20RewardsDepositEvent,
): void {
  const rewardsDeposit = new ERC20RewardsDeposit(
    `${event.transaction.hash.toHex()}-${event.transactionLogIndex}`,
  );
  rewardsDeposit.address = event.address;
  rewardsDeposit.block = event.block.number;
  rewardsDeposit.timestamp = event.block.timestamp;
  rewardsDeposit.txn = makeTransaction(event);
  rewardsDeposit.collection = event.params.collection;
  rewardsDeposit.mintReferral = event.params.mintReferral;
  rewardsDeposit.mintReferralReward = event.params.mintReferralReward;
  rewardsDeposit.createReferral = event.params.createReferral;
  rewardsDeposit.createReferralReward = event.params.createReferralReward;
  rewardsDeposit.zora = event.params.zora;
  rewardsDeposit.zoraReward = event.params.zoraReward;
  rewardsDeposit.currency = event.params.currency;
  rewardsDeposit.tokenId = event.params.tokenId;
  rewardsDeposit.firstMinter = event.params.firstMinter;
  rewardsDeposit.firstMinterReward = event.params.firstMinterReward;

  rewardsDeposit.save();
}
