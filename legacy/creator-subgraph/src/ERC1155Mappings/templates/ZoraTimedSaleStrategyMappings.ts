import {
  MintComment as ZoraTimedMintComment,
  SaleSet,
  SaleSetV2,
  ZoraTimedSaleStrategyRewards as ZoraTimedSaleStrategyRewardsDepositEvent,
  MarketLaunched,
} from "../../../generated/ZoraTimedSaleStrategy1/ZoraTimedSaleStrategy";
import { Address, BigInt } from "@graphprotocol/graph-ts";
import { getSalesConfigKey } from "../../common/getSalesConfigKey";
import { getTokenId } from "../../common/getTokenId";
import { makeTransaction } from "../../common/makeTransaction";
import { SALE_CONFIG_ZORA_TIMED } from "../../constants/salesConfigTypes";
import { getContractId } from "../../common/getContractId";
import {
  SalesStrategyConfig,
  MintComment,
  ZoraTimedSaleStrategyRewardsDeposit,
  ERC20Z,
  SalesConfigZoraTimedSaleStrategy,
} from "../../../generated/schema";
import { getMintCommentId } from "../../common/getMintCommentId";

function getOrCreateErc20Z(
  erc20Address: Address,
  name: string,
  symbol: string,
  pool: Address,
): ERC20Z {
  let erc20Z = ERC20Z.load(erc20Address.toHexString());

  if (erc20Z) return erc20Z;

  erc20Z = new ERC20Z(erc20Address.toHexString());

  erc20Z.name = name;
  erc20Z.symbol = symbol;
  erc20Z.pool = pool;

  erc20Z.save();

  return erc20Z;
}

export function handleZoraTimedSaleStrategySaleSet(event: SaleSet): void {
  const id = getSalesConfigKey(
    event.address,
    event.params.collection,
    event.params.tokenId,
  );

  let sale = SalesConfigZoraTimedSaleStrategy.load(id);
  if (sale) {
    sale.saleEnd = event.params.salesConfig.saleEnd;
    sale.saleStart = event.params.salesConfig.saleStart;
    sale.save();
  } else if (!sale) {
    sale = new SalesConfigZoraTimedSaleStrategy(id);
    sale.configAddress = event.address;
    sale.contract = getContractId(event.params.collection);
    sale.tokenId = event.params.tokenId;
    sale.saleStart = event.params.salesConfig.saleStart;
    sale.saleEnd = event.params.salesConfig.saleEnd;
    sale.erc20z = event.params.erc20zAddress;
    sale.pool = event.params.poolAddress;
    sale.secondaryActivated = false;

    sale.erc20Z = getOrCreateErc20Z(
      event.params.erc20zAddress,
      event.params.salesConfig.name,
      event.params.salesConfig.symbol,
      event.params.poolAddress,
    ).id;

    sale.mintFee = event.params.mintFee;

    const txn = makeTransaction(event);
    sale.txn = txn;
    sale.block = event.block.number;
    sale.timestamp = event.block.timestamp;
    sale.address = event.address;

    sale.save();

    const saleJoin = new SalesStrategyConfig(id);
    if (event.params.tokenId.equals(BigInt.zero())) {
      saleJoin.contract = getContractId(event.params.collection);
    } else {
      saleJoin.tokenAndContract = getTokenId(
        event.params.collection,
        event.params.tokenId,
      );
    }
    saleJoin.zoraTimedMinter = id;
    saleJoin.type = SALE_CONFIG_ZORA_TIMED;
    saleJoin.txn = txn;
    saleJoin.block = event.block.number;
    saleJoin.timestamp = event.block.timestamp;
    saleJoin.address = event.address;
    saleJoin.save();
  }
}

export function handleZoraTimedSaleStrategySaleSetV2(event: SaleSetV2): void {
  const id = getSalesConfigKey(
    event.address,
    event.params.collection,
    event.params.tokenId,
  );

  let sale = SalesConfigZoraTimedSaleStrategy.load(id);

  if (sale) {
    if (!event.params.saleData.saleEnd.equals(BigInt.zero())) {
      sale.saleEnd = event.params.saleData.saleEnd;
    } else {
      sale.saleStart = event.params.saleData.saleStart;
      sale.marketCountdown = event.params.saleData.marketCountdown;
    }

    sale.save();
    return;
  }

  sale = new SalesConfigZoraTimedSaleStrategy(id);

  sale.configAddress = event.address;
  sale.contract = getContractId(event.params.collection);
  sale.tokenId = event.params.tokenId;
  sale.mintFee = event.params.mintFee;
  sale.saleStart = event.params.saleData.saleStart;
  sale.marketCountdown = event.params.saleData.marketCountdown;
  sale.saleEnd = event.params.saleData.saleEnd;
  sale.secondaryActivated = event.params.saleData.secondaryActivated;
  sale.minimumMarketEth = event.params.saleData.minimumMarketEth;
  sale.pool = event.params.saleData.poolAddress;
  sale.erc20z = event.params.saleData.erc20zAddress;
  sale.erc20Z = getOrCreateErc20Z(
    event.params.saleData.erc20zAddress,
    event.params.saleData.name,
    event.params.saleData.symbol,
    event.params.saleData.poolAddress,
  ).id;

  const txn = makeTransaction(event);

  sale.txn = txn;
  sale.block = event.block.number;
  sale.timestamp = event.block.timestamp;
  sale.address = event.address;
  sale.save();

  const saleJoin = new SalesStrategyConfig(id);

  if (event.params.tokenId.equals(BigInt.zero())) {
    saleJoin.contract = getContractId(event.params.collection);
  } else {
    saleJoin.tokenAndContract = getTokenId(
      event.params.collection,
      event.params.tokenId,
    );
  }

  saleJoin.zoraTimedMinter = id;
  saleJoin.type = SALE_CONFIG_ZORA_TIMED;
  saleJoin.txn = txn;
  saleJoin.block = event.block.number;
  saleJoin.timestamp = event.block.timestamp;
  saleJoin.address = event.address;
  saleJoin.save();
}

export function handleMintComment(event: ZoraTimedMintComment): void {
  const mintComment = new MintComment(getMintCommentId(event));
  const tokenAndContract = getTokenId(
    event.params.collection,
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

export function handleZoraTimedSaleStrategyRewardsDeposit(
  event: ZoraTimedSaleStrategyRewardsDepositEvent,
): void {
  const rewardsDeposit = new ZoraTimedSaleStrategyRewardsDeposit(
    `${event.transaction.hash.toHex()}-${event.transactionLogIndex}`,
  );
  rewardsDeposit.address = event.address;
  rewardsDeposit.block = event.block.number;
  rewardsDeposit.timestamp = event.block.timestamp;
  rewardsDeposit.txn = makeTransaction(event);
  rewardsDeposit.creator = event.params.creator;
  rewardsDeposit.creatorReward = event.params.creatorReward;
  rewardsDeposit.collection = event.params.collection;
  rewardsDeposit.tokenId = event.params.tokenId;
  rewardsDeposit.mintReferral = event.params.mintReferral;
  rewardsDeposit.mintReferralReward = event.params.mintReferralReward;
  rewardsDeposit.createReferral = event.params.createReferral;
  rewardsDeposit.createReferralReward = event.params.createReferralReward;
  rewardsDeposit.market = event.params.market;
  rewardsDeposit.marketReward = event.params.marketReward;
  rewardsDeposit.zora = event.params.zoraRecipient;
  rewardsDeposit.zoraReward = event.params.zoraReward;

  rewardsDeposit.save();
}

export function handleMarketLaunched(event: MarketLaunched): void {
  const id = getSalesConfigKey(
    event.address,
    event.params.collection,
    event.params.tokenId,
  );

  const sale = SalesConfigZoraTimedSaleStrategy.load(id);
  if (!sale) {
    return;
  }

  sale.secondaryActivated = true;
  sale.save();
}
