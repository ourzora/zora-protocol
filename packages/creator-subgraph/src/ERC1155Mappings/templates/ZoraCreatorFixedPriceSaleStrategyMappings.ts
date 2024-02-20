import { BigInt } from "@graphprotocol/graph-ts";
import {
  SalesConfigFixedPriceSaleStrategy,
  SalesStrategyConfig,
  MintComment
} from "../../../generated/schema";
import { SaleSet } from "../../../generated/templates/ZoraCreatorFixedPriceSaleStrategy/ZoraCreatorFixedPriceSaleStrategy";
import { getSalesConfigKey } from "../../common/getSalesConfigKey";
import { getTokenId } from "../../common/getTokenId";
import { makeTransaction } from "../../common/makeTransaction";
import { SALE_CONFIG_FIXED_PRICE } from "../../constants/salesConfigTypes";
import { MintComment as Zora1155MintComment } from "../../../generated/templates/ZoraCreatorFixedPriceSaleStrategy/ZoraCreatorFixedPriceSaleStrategy";
import { getMintCommentId } from "../../common/getMintCommentId";
import { getContractId } from "../../common/getContractId";

export function handleFixedPriceStrategySaleSet(event: SaleSet): void {
  const id = getSalesConfigKey(event.address, event.params.mediaContract, event.params.tokenId)
  const sale = new SalesConfigFixedPriceSaleStrategy(id);
  sale.configAddress = event.address;
  sale.contract = getContractId(event.params.mediaContract);
  sale.fundsRecipient = event.params.salesConfig.fundsRecipient;
  sale.pricePerToken = event.params.salesConfig.pricePerToken;
  sale.saleStart = event.params.salesConfig.saleStart;
  sale.saleEnd = event.params.salesConfig.saleEnd;
  sale.maxTokensPerAddress = event.params.salesConfig.maxTokensPerAddress;

  const txn = makeTransaction(event);
  sale.txn = txn;
  sale.block = event.block.number;
  sale.timestamp = event.block.timestamp;
  sale.address = event.address;

  sale.tokenId = event.params.tokenId;
  sale.save();

  // add join
  const saleJoin = new SalesStrategyConfig(id);
  if (event.params.tokenId.equals(BigInt.zero())) {
    saleJoin.contract = getContractId(event.params.mediaContract);
  } else {
    saleJoin.tokenAndContract = getTokenId(event.params.mediaContract, event.params.tokenId);
  }
  saleJoin.fixedPrice = id;
  saleJoin.type = SALE_CONFIG_FIXED_PRICE;
  saleJoin.txn = txn;
  saleJoin.block = event.block.number;
  saleJoin.timestamp = event.block.timestamp;
  saleJoin.address = event.address;
  saleJoin.save();
}

export function handleMintedWithComment(event: Zora1155MintComment): void {
  const mintComment = new MintComment(getMintCommentId(event));
  const tokenAndContract = getTokenId(event.params.tokenContract, event.params.tokenId);
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