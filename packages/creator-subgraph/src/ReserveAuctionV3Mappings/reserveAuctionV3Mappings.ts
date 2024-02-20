import { Address, BigInt, Bytes, ethereum } from '@graphprotocol/graph-ts'
import { Auction } from '../../generated/schema'
import {
  AuctionCreated,
  AuctionBid,
  AuctionCanceled,
  AuctionEnded,
  AuctionReservePriceUpdated,
} from '../../generated/ReserveAuctionV3/ReserveAuctionV3'
import { makeTransaction } from '../common/makeTransaction'

function getAuctionId(tokenContract: Address, tokenId: BigInt): string {
  return `${tokenContract.toHexString()}-${tokenId.toString()}`
}

export function handleAuctionCreated(event: AuctionCreated): void {
  const auctionId = getAuctionId(
    event.params.tokenContract,
    event.params.tokenId
  )
  let auction = Auction.load(auctionId)
  if (!auction) {
    auction = new Auction(auctionId)
  }

  auction.address = event.address
  auction.block = event.block.number
  auction.timestamp = event.block.timestamp
  auction.txn = makeTransaction(event)

  auction.tokenContract = event.params.tokenContract
  auction.tokenId = event.params.tokenId
  auction.seller = event.params.auction.seller
  auction.sellerFundsRecipient = event.params.auction.sellerFundsRecipient
  auction.reservePrice = event.params.auction.reservePrice
  auction.highestBid = event.params.auction.highestBid
  auction.highestBidder = event.params.auction.highestBidder
  auction.startTime = event.params.auction.startTime
  auction.currency = event.params.auction.currency
  auction.firstBidTime = event.params.auction.firstBidTime
  auction.finder = event.params.auction.finder
  auction.duration = event.params.auction.duration
  auction.findersFeeBps = BigInt.fromI32(event.params.auction.findersFeeBps)

  auction.save()
}

export function handleAuctionReservePriceUpdated(
  event: AuctionReservePriceUpdated
): void {
  const auctionId = getAuctionId(
    event.params.tokenContract,
    event.params.tokenId
  )
  let auction = Auction.load(auctionId)
  if (!auction) {
    return
  }

  auction.reservePrice = event.params.auction.reservePrice

  auction.save()
}

export function handleAuctionBid(event: AuctionBid): void {
  const auctionId = getAuctionId(
    event.params.tokenContract,
    event.params.tokenId
  )
  let auction = Auction.load(auctionId)
  if (!auction) {
    return
  }

  auction.firstBidTime = event.params.auction.firstBidTime
  auction.highestBid = event.params.auction.highestBid
  auction.highestBidder = event.params.auction.highestBidder
  auction.finder = event.params.auction.finder
  auction.duration = event.params.auction.duration
  auction.extended = event.params.extended

  auction.save()
}

export function handleAuctionCanceled(event: AuctionCanceled): void {
  const auctionId = getAuctionId(
    event.params.tokenContract,
    event.params.tokenId
  )
  let auction = Auction.load(auctionId)
  if (!auction) {
    return
  }

  auction.canceled = true

  auction.save()
}

export function handleAuctionEnded(event: AuctionEnded): void {
  const auctionId = getAuctionId(event.params.tokenContract, event.params.tokenId)
  let auction = Auction.load(auctionId)
  if (!auction) {
    return
  }

  auction.ended = true

  auction.save()
}
