import confirm from "@inquirer/confirm";
import {
  getCoin,
  getCoinComments,
  prepareUserOperation,
  setApiKey,
  submitUserOperation,
  toGenericCall,
  toUserOperationCalls,
  type ContractCall,
} from "@zoralabs/coins-sdk";
import { Command } from "commander";
import { isAddress, type Address } from "viem";
import type { BundlerClient, SmartAccount } from "viem/account-abstraction";
import { shutdownAnalytics, track } from "../lib/analytics.js";
import {
  CoinArgError,
  coinArgsToRef,
  formatAmbiguousError,
  isCoinTypeKeyword,
  parsePositionalCoinArgs,
  resolveAmbiguousName,
  resolveCoin,
} from "../lib/coin-ref.js";
import {
  COIN_COMMENT_TOKEN_ID,
  COMMENTS_ADDRESS,
  EMPTY_COMMENT_IDENTIFIER,
  coinCommentsAbi,
  commentsAbi,
} from "../lib/comments.js";
import { getApiKey } from "../lib/config.js";
import { BASE_CHAIN_ID } from "../lib/constants.js";
import { apiErrorMessage, serializeError } from "../lib/errors.js";
import { ERROR, safeExit, SUCCESS } from "../lib/exit.js";
import { formatRelativeTime, truncateAddress } from "../lib/format.js";
import { gasErrorSuggestion } from "../lib/gas.js";
import {
  getJson,
  outputData,
  outputErrorAndExit,
  outputJson,
} from "../lib/output.js";
import { createClients, resolveAccounts } from "../lib/wallet.js";

const ZERO_ADDRESS: Address = "0x0000000000000000000000000000000000000000";

/** Resolved coin reference: enough to read or write comments. */
type CoinTarget = { address: Address; name: string };

const resolveApiKey = () => {
  const apiKey = getApiKey();
  if (apiKey) {
    setApiKey(apiKey);
  }
};

/**
 * Resolves the positional coin args (address, `creator-coin <name>`, `trend
 * <name>`, or a bare name) to a single coin address + display name. Exits with a
 * helpful error when the reference is invalid, missing, or ambiguous.
 */
async function resolveCoinTarget(
  json: boolean,
  typeOrId: string | undefined,
  identifier: string | undefined,
  command: string,
): Promise<CoinTarget> {
  // Guard before parsing: parsePositionalCoinArgs assumes a defined first arg
  // (it calls typeOrId.startsWith), so a bare `comment list` would otherwise
  // throw a raw TypeError instead of a usage message.
  if (!typeOrId) {
    return outputErrorAndExit(
      json,
      "Missing coin.",
      `Usage: zora ${command} <coin>`,
    );
  }

  let parsed;
  try {
    parsed = parsePositionalCoinArgs(typeOrId, identifier);
  } catch (err) {
    if (err instanceof CoinArgError) {
      return outputErrorAndExit(json, err.message, err.suggestion);
    }
    throw err;
  }

  resolveApiKey();

  if (parsed.kind === "address") {
    if (!isAddress(parsed.address)) {
      return outputErrorAndExit(json, `Invalid address: ${parsed.address}`);
    }
    // Look up the name for nicer output, but don't fail the command if the
    // metadata lookup misses — the address is enough to read/write comments.
    let name: string = parsed.address;
    try {
      const response = await getCoin({ address: parsed.address });
      name = response.data?.zora20Token?.name ?? parsed.address;
    } catch {
      // ignore — fall back to the address as the display name
    }
    return { address: parsed.address as Address, name };
  }

  if (parsed.kind === "ambiguous-name") {
    let ambResult;
    try {
      ambResult = await resolveAmbiguousName(parsed.name);
    } catch (err) {
      return outputErrorAndExit(
        json,
        `Request failed: ${err instanceof Error ? err.message : String(err)}`,
      );
    }
    if (ambResult.kind === "not-found") {
      return outputErrorAndExit(json, ambResult.message);
    }
    if (ambResult.kind === "ambiguous") {
      const { message, suggestion } = formatAmbiguousError(
        parsed.name,
        ambResult.creator,
        ambResult.trend,
        command,
      );
      return outputErrorAndExit(json, message, suggestion);
    }
    return {
      address: ambResult.coin.address as Address,
      name: ambResult.coin.name,
    };
  }

  // typed (creator-coin / trend)
  try {
    const result = await resolveCoin(coinArgsToRef(parsed));
    if (result.kind === "not-found") {
      return outputErrorAndExit(json, result.message, result.suggestion);
    }
    return {
      address: result.coin.address as Address,
      name: result.coin.name,
    };
  } catch (err) {
    return outputErrorAndExit(
      json,
      `Request failed: ${err instanceof Error ? err.message : String(err)}`,
    );
  }
}

/**
 * Posts a comment from a smart wallet by wrapping the contract call in a user
 * operation, mirroring the EOA `writeContract` path. Returns the settled tx
 * hash. Follows the same pattern as send.ts's `sendCallViaSmartWallet`.
 */
async function commentViaSmartWallet(
  call: ContractCall,
  bundlerClient: BundlerClient,
  account: SmartAccount,
): Promise<`0x${string}`> {
  const userOperation = await prepareUserOperation({
    bundlerClient,
    account,
    calls: toUserOperationCalls([toGenericCall(call)]),
  });

  const receipt = await submitUserOperation({
    bundlerClient,
    account,
    userOperation,
  });

  if (!receipt.success) {
    throw new Error(
      `User operation reverted${receipt.reason ? `: ${receipt.reason}` : ""}`,
    );
  }

  return receipt.receipt.transactionHash;
}

// --- comment (post) ---

export const commentCommand = new Command("comment")
  .description("Comment on a coin you hold")
  .argument(
    "[typeOrId]",
    "Type prefix (creator-coin, trend) or coin address/name",
  )
  .argument("[nameOrText]", "Coin name (with a type prefix) or comment text")
  .argument("[text]", "Comment text when a type prefix is used")
  .option("--referrer <address>", "Referrer address for spark rewards")
  .option("--yes", "Skip confirmation and post directly")
  .action(async function (
    this: Command,
    typeOrId: string,
    nameOrText: string | undefined,
    text: string | undefined,
    opts: { referrer?: string; yes?: boolean },
  ) {
    const json = getJson(this);

    // The comment text is always the trailing positional. A type prefix
    // (creator-coin / trend) makes the coin reference span two args, so the
    // text shifts to the third arg; otherwise the coin is one arg and the text
    // is the second. Without this, `comment creator-coin <name> "<text>"` would
    // silently post the coin name as the comment (the type prefix consumes the
    // text slot).
    const typed = isCoinTypeKeyword(typeOrId);
    const coinIdentifier = typed ? nameOrText : undefined;
    const commentText = typed ? text : nameOrText;

    if (!commentText || commentText.trim().length === 0) {
      return outputErrorAndExit(
        json,
        "Missing comment text.",
        'Usage: zora comment <coin> "your comment"',
      );
    }

    if (opts.referrer && !isAddress(opts.referrer)) {
      return outputErrorAndExit(json, `Invalid --referrer: ${opts.referrer}`);
    }

    const coin = await resolveCoinTarget(
      json,
      typeOrId,
      coinIdentifier,
      "comment",
    );

    const { privateKeyAccount, smartWalletAccount } = await resolveAccounts();
    const { publicClient, walletClient, bundlerClient } = createClients(
      privateKeyAccount,
      smartWalletAccount,
    );

    if (!!smartWalletAccount && !bundlerClient) {
      return outputErrorAndExit(
        json,
        "Failed to obtain bundler client for your smart wallet. Please try again. If the problem persists, ensure your smart wallet is setup correctly.",
      );
    }

    // The comment is attributed to whichever address acts as msg.sender: the
    // smart wallet (via the bundler) when configured, otherwise the EOA. Using
    // the smart wallet keeps the comment tied to the agent's Zora profile.
    const commenter: Address =
      smartWalletAccount?.address ?? privateKeyAccount.address;

    // The Comments contract only lets coin holders (or the owner) comment, and
    // owners comment for free while everyone else includes one spark. Read the
    // spark price, ownership, and the commenter's balance up front so we can
    // fail fast with a clear message instead of letting the transaction revert
    // with NotTokenHolderOrAdmin().
    let sparkValue: bigint;
    let isOwner: boolean;
    let balance: bigint;
    try {
      [sparkValue, isOwner, balance] = await Promise.all([
        publicClient.readContract({
          address: COMMENTS_ADDRESS,
          abi: commentsAbi,
          functionName: "sparkValue",
        }),
        publicClient.readContract({
          address: coin.address,
          abi: coinCommentsAbi,
          functionName: "isOwner",
          args: [commenter],
        }),
        publicClient.readContract({
          address: coin.address,
          abi: coinCommentsAbi,
          functionName: "balanceOf",
          args: [commenter],
        }),
      ]);
    } catch (err) {
      return outputErrorAndExit(
        json,
        `Failed to read comment requirements: ${err instanceof Error ? err.message : String(err)}`,
      );
    }

    // Pre-flight: only holders/owners can comment. Bail before building or
    // sending anything so the agent gets an actionable message (and no wasted
    // round trip) instead of an on-chain revert.
    if (!isOwner && balance === 0n) {
      return outputErrorAndExit(
        json,
        `You must hold ${coin.name} to comment on it.`,
        `Buy some first: zora buy ${coin.address} --eth 0.001`,
      );
    }

    const value = isOwner ? 0n : sparkValue;
    const referrer = (opts.referrer as Address | undefined) ?? ZERO_ADDRESS;

    const call: ContractCall<typeof commentsAbi, "comment"> = {
      address: COMMENTS_ADDRESS,
      abi: commentsAbi,
      functionName: "comment",
      args: [
        commenter,
        coin.address,
        COIN_COMMENT_TOKEN_ID,
        commentText,
        EMPTY_COMMENT_IDENTIFIER,
        // commenterSmartWalletOwner is only needed when an EOA comments on
        // behalf of a smart wallet; here msg.sender *is* the commenter, so the
        // zero address is correct for both the EOA and smart wallet paths.
        ZERO_ADDRESS,
        referrer,
      ],
      value,
    };

    if (!opts.yes && !json) {
      console.log(`\n Comment on ${coin.name}\n`);
      console.log(`   Coin     ${coin.address}`);
      console.log(`   As       ${commenter}`);
      console.log(`   Cost     ${isOwner ? "free (coin owner)" : "1 spark"}`);
      console.log(`   Text     ${commentText}\n`);

      const ok = await confirm({ message: "Post comment?", default: false });
      if (!ok) {
        console.error("Aborted.");
        return safeExit(SUCCESS);
      }
    }

    let txHash: `0x${string}`;
    try {
      txHash = smartWalletAccount
        ? await commentViaSmartWallet(call, bundlerClient!, smartWalletAccount)
        : await walletClient.writeContract(call);
    } catch (err) {
      track("cli_comment", {
        action: "post",
        coin_address: coin.address,
        output_format: json ? "json" : "static",
        success: false,
        error_type: err instanceof Error ? err.constructor.name : "unknown",
        error: serializeError(err),
      });
      await shutdownAnalytics();
      const rawMessage = err instanceof Error ? err.message : String(err);
      // The Comments contract only lets holders (or the coin's admin/owner)
      // comment. Non-holders revert with NotTokenHolderOrAdmin() (selector
      // 0xd8a26f99) — surface an actionable message instead of a raw revert.
      const notHolder =
        rawMessage.includes("NotTokenHolderOrAdmin") ||
        rawMessage.includes("0xd8a26f99");
      if (notHolder) {
        return outputErrorAndExit(
          json,
          `You must hold ${coin.name} to comment on it.`,
          `Buy some first: zora buy ${coin.address} --eth 0.001`,
        );
      }
      return outputErrorAndExit(
        json,
        `Failed to post comment: ${rawMessage}`,
        gasErrorSuggestion(err, smartWalletAccount ?? privateKeyAccount),
      );
    }

    // Smart wallet sends settle inside the user operation; only EOA
    // transactions need an explicit receipt wait.
    if (!smartWalletAccount) {
      await publicClient.waitForTransactionReceipt({ hash: txHash });
    }

    if (json) {
      outputJson({
        action: "comment",
        coin: { name: coin.name, address: coin.address },
        commenter,
        text: commentText,
        tx: txHash,
      });
    } else {
      console.log(`\n Comment posted on ${coin.name}\n`);
      console.log(`   As       ${commenter}`);
      console.log(`   Text     ${commentText}`);
      console.log(`   Tx       ${txHash}\n`);
    }

    track("cli_comment", {
      action: "post",
      coin_address: coin.address,
      output_format: json ? "json" : "static",
      success: true,
      tx_hash: txHash,
    });
  });

// --- comment list (read) ---

type CommentNode = {
  commentId: string;
  userAddress: string;
  comment: string;
  timestamp: number;
  userProfile?: { handle: string };
  replies: { count: number };
};

function commenterLabel(node: CommentNode): string {
  const handle = node.userProfile?.handle;
  if (handle && !handle.startsWith("0x") && !handle.includes("…")) {
    return `@${handle}`;
  }
  return truncateAddress(node.userAddress);
}

commentCommand
  .command("list")
  .description("List comments on a coin")
  .argument(
    "[typeOrId]",
    "Type prefix (creator-coin, trend) or coin address/name",
  )
  .argument("[identifier]", "Coin name (when type prefix is given)")
  .option("--limit <n>", "Number of comments per page (max 100)", "20")
  .option("--after <cursor>", "Pagination cursor from a previous result")
  .action(async function (
    this: Command,
    typeOrId: string,
    identifier: string | undefined,
    opts: { limit?: string; after?: string },
  ) {
    const json = getJson(this);

    const limit = parseInt(opts.limit ?? "20", 10);
    if (isNaN(limit) || limit <= 0 || limit > 100) {
      return outputErrorAndExit(
        json,
        `Invalid --limit value: ${opts.limit}. Must be an integer between 1 and 100.`,
        "Usage: zora comment list <coin> --limit 20",
      );
    }

    const coin = await resolveCoinTarget(
      json,
      typeOrId,
      identifier,
      "comment list",
    );

    let response;
    try {
      response = await getCoinComments({
        address: coin.address,
        chain: BASE_CHAIN_ID,
        count: limit,
        after: opts.after,
      });
    } catch (err) {
      return outputErrorAndExit(
        json,
        `Failed to fetch comments: ${apiErrorMessage(err)}`,
      );
    }

    const zoraComments = response.data?.zora20Token?.zoraComments;
    const nodes: CommentNode[] = (zoraComments?.edges ?? []).map(
      (e) => e.node as CommentNode,
    );
    const totalCount = zoraComments?.count ?? nodes.length;
    const pageInfo = zoraComments?.pageInfo;

    outputData(json, {
      json: {
        coin: { name: coin.name, address: coin.address },
        totalComments: totalCount,
        comments: nodes.map((n) => ({
          commentId: n.commentId,
          author: n.userProfile?.handle ?? n.userAddress,
          authorAddress: n.userAddress,
          text: n.comment,
          timestamp: n.timestamp,
          replyCount: n.replies?.count ?? 0,
        })),
        ...(pageInfo?.hasNextPage && pageInfo.endCursor
          ? { nextCursor: pageInfo.endCursor }
          : {}),
      },
      render: () => {
        if (nodes.length === 0) {
          console.log(`\nNo comments yet on ${coin.name}.\n`);
          return;
        }
        console.log(
          `\n Comments · ${coin.name}  (${nodes.length} of ${totalCount})\n`,
        );
        for (const node of nodes) {
          const when = formatRelativeTime(new Date(node.timestamp * 1000));
          const replies =
            node.replies?.count > 0
              ? `  ·  ${node.replies.count} ${
                  node.replies.count === 1 ? "reply" : "replies"
                }`
              : "";
          console.log(`   ${commenterLabel(node)}  ·  ${when}${replies}`);
          console.log(`   ${node.comment}\n`);
        }
        if (pageInfo?.hasNextPage && pageInfo.endCursor) {
          console.log(
            `   Next page: zora comment list ${coin.address} --limit ${limit} --after ${pageInfo.endCursor}\n`,
          );
        }
      },
    });

    track("cli_comment", {
      action: "list",
      coin_address: coin.address,
      result_count: nodes.length,
      output_format: json ? "json" : "static",
    });
  });
