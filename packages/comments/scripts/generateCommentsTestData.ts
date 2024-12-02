import {
  parseEther,
  PublicClient,
  Address,
  WalletClient,
  Hex,
  Chain,
  Transport,
  numberToHex,
  zeroAddress,
  keccak256,
  Account,
  TransactionReceipt,
  parseEventLogs,
} from "viem";
import { zoraCreator1155ImplABI } from "@zoralabs/zora-1155-contracts";
import { privateKeyToAccount } from "viem/accounts";
import { zoraTimedSaleStrategyImplABI } from "./abis";
import { zoraSepolia } from "viem/chains";
import { CommentIdentifier } from "../package/types";
import { getCommentsAddress } from "./getCommentsAddresses";
import { commentsImplABI } from "../package/wagmiGenerated";
import { getChainConfig } from "./utils";
// load env variables
import dotenv from "dotenv";
dotenv.config();

const MINT_FEE = parseEther("0.000111");
const SPARK_VALUE = parseEther("0.000001");
const TEST_1155_CONTRACT = "0xD42557F24034b53e7340A40bb5813eF9Ba88F2b4";
const TEST_TOKEN_ID = 3n;
const ZORA_TIMED_SALE_STRATEGY = "0x777777722D078c97c6ad07d9f36801e653E356Ae";
const GAS_FEE = parseEther("0.000001");

const getAccountFromEnv = ({ keyName }: { keyName: string }) => {
  const privateKey = process.env[keyName] as Address;
  if (!privateKey) {
    throw new Error(`${keyName} not found in environment`);
  }
  return privateKeyToAccount(privateKey);
};

const getCommentIdentifierFromReceipt = ({
  receipt,
}: {
  receipt: TransactionReceipt;
}): CommentIdentifier => {
  const logs = parseEventLogs({
    abi: commentsImplABI,
    logs: receipt.logs,
    eventName: "Commented",
  });

  if (logs.length === 0) {
    throw new Error("No Commented event found in receipt");
  }

  return logs[0]!.args.commentIdentifier;
};

const waitForReceiptAndEnsureSuccess = async ({
  hash,
  publicClient,
}: {
  hash: Hex;
  publicClient: PublicClient<Transport, Chain>;
}) => {
  const receipt = await publicClient.waitForTransactionReceipt({ hash });
  if (receipt.status !== "success") {
    throw new Error("Transaction failed");
  }

  return receipt;
};

const mintIfNotOwner = async ({
  walletClient,
  publicClient,
  account,
  commenter,
}: {
  walletClient: WalletClient<Transport, Chain>;
  publicClient: PublicClient<Transport, Chain>;
  account: Account;
  commenter: Account;
}) => {
  // check if commenter has a mint on 1155
  const balance = await publicClient.readContract({
    abi: zoraCreator1155ImplABI,
    address: TEST_1155_CONTRACT,
    functionName: "balanceOf",
    args: [commenter.address, TEST_TOKEN_ID],
  });

  if (balance === 0n) {
    console.log("minting token to commenter");

    const tx = await walletClient.writeContract({
      abi: zoraTimedSaleStrategyImplABI,
      address: ZORA_TIMED_SALE_STRATEGY,
      functionName: "mint",
      account,
      args: [
        commenter.address,
        1n,
        TEST_1155_CONTRACT,
        TEST_TOKEN_ID,
        zeroAddress,
        "",
      ],
      value: MINT_FEE,
    });

    await waitForReceiptAndEnsureSuccess({ hash: tx, publicClient });
  }
};

const generateTestComments = async ({
  walletClient,
  publicClient,
  commentsAddress,
  account,
  commenter,
  contractAddress,
  tokenId,
}: {
  walletClient: WalletClient<Transport, Chain>;
  publicClient: PublicClient<Transport, Chain>;
  commentsAddress: Address;
  account: Account;
  commenter: Account;
  contractAddress: Address;
  tokenId: bigint;
}) => {
  await mintIfNotOwner({ walletClient, publicClient, account, commenter });

  const emptyCommentIdentifier: CommentIdentifier = {
    commenter: zeroAddress,
    contractAddress: zeroAddress,
    tokenId: 0n,
    nonce: keccak256(numberToHex(0)),
  } as const;

  console.log("sending 2 sparks worth of eth to commenter");

  // send 2 sparks worth of eth to commenter
  let tx = await walletClient.sendTransaction({
    account,
    to: commenter.address,
    value: (SPARK_VALUE + GAS_FEE) * 2n,
  });
  await waitForReceiptAndEnsureSuccess({ hash: tx, publicClient });

  console.log("commenting");

  const commentIdentifier = await writeCommentToContract({
    walletClient,
    publicClient,
    commentsAddress,
    commenter,
    contractAddress,
    tokenId,
    text: "This is a test comment",
    replyTo: emptyCommentIdentifier,
  });

  console.log("replying to comment");

  const replyCommentIdentifier = await writeCommentToContract({
    walletClient,
    publicClient,
    commentsAddress,
    commenter,
    contractAddress,
    tokenId,
    text: "This is a test reply",
    replyTo: commentIdentifier,
  });

  return { commentIdentifier, replyCommentIdentifier };
};

const writeCommentToContract = async ({
  walletClient,
  publicClient,
  commentsAddress,
  commenter,
  contractAddress,
  tokenId,
  text,
  replyTo,
}: {
  walletClient: WalletClient<Transport, Chain>;
  publicClient: PublicClient<Transport, Chain>;
  commentsAddress: Address;
  commenter: Account | Address;
  contractAddress: Address;
  tokenId: bigint;
  text: string;
  replyTo: CommentIdentifier;
}): Promise<CommentIdentifier> => {
  const tx = await walletClient.writeContract({
    abi: commentsImplABI,
    address: commentsAddress,
    functionName: "comment",
    account: commenter,
    args: [
      typeof commenter === "string" ? commenter : commenter.address,
      contractAddress,
      tokenId,
      text,
      replyTo,
      zeroAddress,
      zeroAddress,
    ],
    value: SPARK_VALUE,
  });

  const receipt = await waitForReceiptAndEnsureSuccess({
    hash: tx,
    publicClient,
  });

  return getCommentIdentifierFromReceipt({ receipt });
};

const sendSparksEth = async ({
  walletClient,
  publicClient,
  account,
  recipient,
  value,
}: {
  walletClient: WalletClient<Transport, Chain>;
  publicClient: PublicClient<Transport, Chain>;
  account: Account;
  recipient: Address;
  value: bigint;
}) => {
  console.log("sending sparks worth of eth to recipient + gas");
  const tx = await walletClient.sendTransaction({
    account,
    to: recipient,
    value,
  });
  await waitForReceiptAndEnsureSuccess({ hash: tx, publicClient });
};

const sparkComment = async ({
  walletClient,
  publicClient,
  commentsAddress,
  account,
  sparker,
  commentIdentifier,
}: {
  walletClient: WalletClient<Transport, Chain>;
  publicClient: PublicClient<Transport, Chain>;
  commentsAddress: Address;
  account: Account;
  sparker: Account;
  commentIdentifier: CommentIdentifier;
}) => {
  await sendSparksEth({
    walletClient,
    publicClient,
    account,
    recipient: sparker.address,
    value: SPARK_VALUE + GAS_FEE,
  });

  console.log("sparking comment");

  // spark the comment
  const tx = await walletClient.writeContract({
    abi: commentsImplABI,
    address: commentsAddress,
    functionName: "sparkComment",
    account: sparker,
    args: [commentIdentifier, 1n, zeroAddress],
    value: SPARK_VALUE,
  });

  await waitForReceiptAndEnsureSuccess({ hash: tx, publicClient });
};

export const generateCommentsTestData = async () => {
  const { walletClient, publicClient } = await getChainConfig("zora-sepolia");

  const commentsAddress = (await getCommentsAddress(zoraSepolia.id)).COMMENTS;

  const account = getAccountFromEnv({ keyName: "PRIVATE_KEY" });

  const commenter = getAccountFromEnv({ keyName: "COMMENTER_PRIVATE_KEY" });
  const sparker = getAccountFromEnv({ keyName: "SPARKER_PRIVATE_KEY" });

  const { commentIdentifier, replyCommentIdentifier } =
    await generateTestComments({
      walletClient,
      publicClient,
      commentsAddress,
      account,
      commenter,
      contractAddress: TEST_1155_CONTRACT,
      tokenId: TEST_TOKEN_ID,
    });

  // spark the comment twice
  await sparkComment({
    walletClient,
    publicClient,
    commentsAddress,
    account,
    sparker,
    commentIdentifier,
  });

  await sparkComment({
    walletClient,
    publicClient,
    commentsAddress,
    account,
    sparker,
    commentIdentifier,
  });

  // spark the reply comment
  await sparkComment({
    walletClient,
    publicClient,
    commentsAddress,
    account,
    sparker,
    commentIdentifier: replyCommentIdentifier,
  });
};

generateCommentsTestData();
