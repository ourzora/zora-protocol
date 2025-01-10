import { BigInt, Bytes } from "@graphprotocol/graph-ts";
import {
  BackfilledComment,
  Commented,
  SparkedComment,
} from "../../../generated/Comments/Comments";
import { Comment } from "../../../generated/schema";
import { getTokenId } from "../../common/getTokenId";
import { makeTransaction } from "../../common/makeTransaction";

export const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

export function getCommentId(id: Bytes): string {
  return `${id.toHex()}`;
}

export function setComment(
  comment: Comment,
  text: string,
  tokenId: BigInt,
  nonce: Bytes,
  commenter: Bytes,
  contractAddress: Bytes,
  replyToId: Bytes,
  referrer: Bytes,
  timestamp: BigInt,
  sparksQuantity: BigInt,
  commentId: Bytes,
): void {
  comment.commentText = text;
  comment.tokenId = tokenId;
  comment.nonce = nonce;
  comment.commenter = commenter;
  comment.contractAddress = contractAddress;
  comment.replyToId = replyToId;
  comment.referrer = referrer;
  comment.commentTimestamp = timestamp;
  comment.sparksQuantity = sparksQuantity;
  comment.commentId = commentId;
  comment.replyCount = BigInt.zero();

  const parentComment = Comment.load(getCommentId(replyToId));
  if (parentComment != null) {
    parentComment.replyCount = parentComment.replyCount.plus(BigInt.fromU32(1));
    parentComment.save();
  }

  comment.save();
}

export function handleCommented(event: Commented): void {
  const comment = new Comment(getCommentId(event.params.commentId));
  const tokenAndContract = getTokenId(
    event.params.commentIdentifier.contractAddress,
    event.params.commentIdentifier.tokenId,
  );
  comment.tokenAndContract = tokenAndContract;

  comment.txn = makeTransaction(event);
  comment.block = event.block.number;
  comment.timestamp = event.block.timestamp;
  comment.address = event.address;

  setComment(
    comment,
    event.params.text,
    event.params.commentIdentifier.tokenId,
    event.params.commentIdentifier.nonce,
    event.params.commentIdentifier.commenter,
    event.params.commentIdentifier.contractAddress,
    event.params.replyToId,
    event.params.referrer,
    event.params.timestamp,
    BigInt.zero(),
    event.params.commentId,
  );

  comment.save();
}

export function handleSparkedComment(event: SparkedComment): void {
  const comment = Comment.load(getCommentId(event.params.commentId));
  if (comment == null) {
    return;
  }
  comment.sparksQuantity = comment.sparksQuantity.plus(
    event.params.sparksQuantity,
  );
  comment.save();
}

export function handleBackfilledComment(event: BackfilledComment): void {
  var comment = Comment.load(getCommentId(event.params.commentId));

  if (comment != null) {
    return;
  }

  comment = new Comment(getCommentId(event.params.commentId));
  const tokenAndContract = getTokenId(
    event.params.commentIdentifier.contractAddress,
    event.params.commentIdentifier.tokenId,
  );
  comment.tokenAndContract = tokenAndContract;

  comment.txn = makeTransaction(event);
  comment.block = event.block.number;
  comment.timestamp = event.block.timestamp;
  comment.address = event.address;

  setComment(
    comment,
    event.params.text,
    event.params.commentIdentifier.tokenId,
    event.params.commentIdentifier.nonce,
    event.params.commentIdentifier.commenter,
    event.params.commentIdentifier.contractAddress,
    new Bytes(0),
    Bytes.fromHexString(ZERO_ADDRESS),
    event.params.timestamp,
    BigInt.zero(),
    event.params.commentId,
  );

  comment.save();
}
