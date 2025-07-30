import { MintComment as MintsManagerMintComment } from "../../generated/MintsManager/MintsManager";
import { getMintCommentId } from "../common/getMintCommentId";
import { MintComment } from "../../generated/schema";
import { getTokenId } from "../common/getTokenId";
import { makeTransaction } from "../common/makeTransaction";

export function handleMintComment(event: MintsManagerMintComment): void {
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
