import confirm from "@inquirer/confirm";
import { Command } from "commander";
import { shutdownAnalytics, track } from "../lib/analytics.js";
import { isCoinTypeKeyword } from "../lib/coin-ref.js";
import { BASE_CHAIN_NAME } from "../lib/agent/zora-client.js";
import {
  COIN_OFF_CHAIN_TOKEN_ID,
  MAX_COMMENT_LENGTH,
  createOffChainComment,
  listCoinComments,
  type MergedComment,
  type OffChainCommentResult,
} from "../lib/comments.js";
import { resolveCoinTarget } from "../lib/comment-target.js";
import { getPrivateKey } from "../lib/config.js";
import { BASE_CHAIN_ID } from "../lib/constants.js";
import { apiErrorMessage, formatError, serializeError } from "../lib/errors.js";
import { formatRelativeTime, truncateAddress } from "../lib/format.js";
import { resolveMentions, toPlainMentions } from "../lib/mentions.js";
import { safeExit, SUCCESS } from "../lib/exit.js";
import { getJson, outputData, outputErrorAndExit } from "../lib/output.js";
import { ensurePrivySession } from "../lib/privy-session.js";
import { normalizeKey } from "../lib/wallet.js";

/**
 * Resolves the Privy access token for the configured wallet, reusing a cached
 * session where possible (a full SIWE sign-in is rate-limited — see
 * {@link ensurePrivySession}). Exits with guidance when sign-in fails.
 */
async function resolveToken(json: boolean, key: string): Promise<string> {
  try {
    const session = await ensurePrivySession({ privateKey: normalizeKey(key) });
    return session.accessToken;
  } catch (err) {
    return outputErrorAndExit(json, `Sign-in failed: ${formatError(err)}`);
  }
}

// --- comment (post) ---

/**
 * Posts a comment on a coin through Zora's backend (off-chain): no transaction,
 * no spark payment, and no coin-holding requirement — any signed-in profile can
 * comment, subject to the backend's rate limit and moderation gates. `@handle`
 * mentions are resolved and encoded so they link and notify.
 */
export const commentCommand = new Command("comment")
  .description("Comment on a coin")
  .argument(
    "[typeOrId]",
    "Type prefix (creator-coin, trend) or coin address/name",
  )
  .argument("[nameOrText]", "Coin name (with a type prefix) or comment text")
  .argument("[text]", "Comment text when a type prefix is used")
  .option("--yes", "Skip confirmation and post directly")
  .action(async function (
    this: Command,
    typeOrId: string,
    nameOrText: string | undefined,
    text: string | undefined,
    opts: { yes?: boolean },
  ) {
    const json = getJson(this);

    // The comment text is always the trailing positional. A type prefix
    // (creator-coin / trend) makes the coin reference span two args, so the
    // text shifts to the third arg; otherwise the coin is one arg and the text
    // is the second.
    const typed = isCoinTypeKeyword(typeOrId);
    const coinIdentifier = typed ? nameOrText : undefined;
    const commentText = (typed ? text : nameOrText)?.trim();

    if (!commentText || commentText.length === 0) {
      return outputErrorAndExit(
        json,
        "Missing comment text.",
        'Usage: zora comment <coin> "your comment"',
      );
    }

    if (commentText.length > MAX_COMMENT_LENGTH) {
      return outputErrorAndExit(
        json,
        `Comment is too long (${commentText.length} characters).`,
        `Comments are limited to ${MAX_COMMENT_LENGTH} characters.`,
      );
    }

    const coin = await resolveCoinTarget(
      json,
      typeOrId,
      coinIdentifier,
      "comment",
    );

    const key = process.env.ZORA_PRIVATE_KEY || getPrivateKey();
    if (!key) {
      return outputErrorAndExit(
        json,
        "No wallet configured.",
        "Run 'zora agent create' to set up your Zora agent.",
      );
    }

    // Encode @mentions into markdown-link tokens the backend understands (see
    // ../lib/mentions.ts). Handles that don't resolve are left as plain text, so
    // a stray `@` never blocks the comment.
    const { text: encodedText, resolved: mentions } =
      await resolveMentions(commentText);

    // The backend's length limit applies to the stored (encoded) text, so check
    // after mention resolution — the tokens are longer than the typed `@handle`.
    if (encodedText.length > MAX_COMMENT_LENGTH) {
      return outputErrorAndExit(
        json,
        `Comment is too long (${encodedText.length} characters after resolving mentions).`,
        `Comments are limited to ${MAX_COMMENT_LENGTH} characters.`,
      );
    }

    if (!opts.yes && !json) {
      console.log(`\n Comment on ${coin.name}\n`);
      console.log(`   Coin     ${coin.address}`);
      console.log(`   Text     ${commentText}`);
      if (mentions.length > 0) {
        console.log(
          `   Mentions ${mentions.map((m) => `@${m.handle}`).join(", ")}`,
        );
      }
      console.log("");

      const ok = await confirm({ message: "Post comment?", default: false });
      if (!ok) {
        console.error("Aborted.");
        return safeExit(SUCCESS);
      }
    }

    // Sign in only after the user confirms, so we don't burn a Privy session on
    // an aborted post.
    const token = await resolveToken(json, key);

    let result: OffChainCommentResult;
    try {
      result = await createOffChainComment(token, {
        chainName: BASE_CHAIN_NAME,
        contractAddress: coin.address,
        tokenId: COIN_OFF_CHAIN_TOKEN_ID,
        text: encodedText,
      });
    } catch (err) {
      track("cli_comment", {
        action: "post",
        coin_address: coin.address,
        output_format: json ? "json" : "static",
        success: false,
        off_chain: true,
        mention_count: mentions.length,
        error_type: err instanceof Error ? err.constructor.name : "unknown",
        error: serializeError(err),
      });
      await shutdownAnalytics();
      return outputErrorAndExit(
        json,
        `Failed to post comment: ${formatError(err)}`,
        "Check the coin and try again. Off-chain comments are rate limited.",
      );
    }

    track("cli_comment", {
      action: "post",
      coin_address: coin.address,
      output_format: json ? "json" : "static",
      success: true,
      off_chain: true,
      comment_id: result.commentId,
      mention_count: mentions.length,
    });

    outputData(json, {
      json: {
        action: "comment",
        offChain: true,
        coin: { name: coin.name, address: coin.address },
        commentId: result.commentId,
        text: result.text,
        commentedAt: result.commentedAt,
        ...(result.handle ? { handle: result.handle } : {}),
        ...(mentions.length > 0
          ? { mentions: mentions.map((m) => m.handle) }
          : {}),
      },
      render: () => {
        console.log(`\n Comment posted on ${coin.name}\n`);
        if (result.handle) console.log(`   As       @${result.handle}`);
        // Show mention tokens as plain @handle for readability.
        console.log(`   Text     ${toPlainMentions(result.text)}`);
        console.log(`   Id       ${result.commentId}\n`);
      },
    });
  });

// --- comment list (read, merged on-chain + off-chain) ---

/** A human label for a commenter: `@handle` when real, else a truncated address. */
function commenterLabel(comment: MergedComment): string {
  const handle = comment.handle;
  if (handle && !handle.startsWith("0x") && !handle.includes("…")) {
    return `@${handle}`;
  }
  if (comment.authorAddress) return truncateAddress(comment.authorAddress);
  return "unknown";
}

commentCommand
  .command("list")
  .description("List comments on a coin (merged on-chain + off-chain)")
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

    // Reading the merged thread is a public SDK call (API key auth via
    // resolveCoinTarget's resolveApiKey) — no wallet/session needed.
    let page;
    try {
      page = await listCoinComments({
        chainId: BASE_CHAIN_ID,
        address: coin.address,
        first: limit,
        after: opts.after,
      });
    } catch (err) {
      track("cli_comment", {
        action: "list",
        coin_address: coin.address,
        output_format: json ? "json" : "static",
        success: false,
        error_type: err instanceof Error ? err.constructor.name : "unknown",
        error: serializeError(err),
      });
      await shutdownAnalytics();
      return outputErrorAndExit(
        json,
        `Failed to fetch comments: ${apiErrorMessage(err)}`,
      );
    }

    const { comments, totalCount, nextCursor } = page;
    const offChainCount = comments.filter((c) => c.offChain).length;

    outputData(json, {
      json: {
        coin: { name: coin.name, address: coin.address },
        totalComments: totalCount,
        comments: comments.map((c) => ({
          commentId: c.commentId,
          offChain: c.offChain,
          author: c.handle ?? c.authorAddress,
          ...(c.authorAddress ? { authorAddress: c.authorAddress } : {}),
          text: c.text,
          timestamp: c.timestamp,
          sparkCount: c.sparkCount,
          replyCount: c.replyCount,
        })),
        ...(nextCursor ? { nextCursor } : {}),
      },
      render: () => {
        if (comments.length === 0) {
          console.log(`\nNo comments yet on ${coin.name}.\n`);
          return;
        }
        console.log(
          `\n Comments · ${coin.name}  (${comments.length} of ${totalCount})\n`,
        );
        for (const comment of comments) {
          const when =
            comment.timestamp > 0
              ? formatRelativeTime(new Date(comment.timestamp * 1000))
              : "";
          const replies =
            comment.replyCount > 0
              ? `  ·  ${comment.replyCount} ${
                  comment.replyCount === 1 ? "reply" : "replies"
                }`
              : "";
          const meta = [when, replies].filter(Boolean).join("");
          console.log(
            `   ${commenterLabel(comment)}${meta ? `  ·  ${meta}` : ""}`,
          );
          console.log(`   ${toPlainMentions(comment.text)}\n`);
        }
        if (nextCursor) {
          console.log(
            `   Next page: zora comment list ${coin.address} --limit ${limit} --after ${nextCursor}\n`,
          );
        }
      },
    });

    track("cli_comment", {
      action: "list",
      coin_address: coin.address,
      output_format: json ? "json" : "static",
      success: true,
      result_count: comments.length,
      offchain_count: offChainCount,
      onchain_count: comments.length - offChainCount,
    });
  });
