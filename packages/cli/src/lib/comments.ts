import type { Address, Hex } from "viem";

/**
 * The Zora Comments protocol contract. Deployed deterministically to the same
 * address on every supported chain (including Base), so a single constant is
 * sufficient for the Base-only CLI.
 *
 * See packages/comments/addresses/8453.json.
 */
export const COMMENTS_ADDRESS: Address =
  "0x7777777C2B3132e03a65721a41745C07170a5877";

/**
 * Coins (zora20 ERC-20 tokens) are commented on with `tokenId` 0 — the Comments
 * contract detects a coin via the {@link ICoinComments} interface and treats the
 * coin contract address as the comment target.
 */
export const COIN_COMMENT_TOKEN_ID = 0n;

/**
 * A `CommentIdentifier` that signals "this is a top-level comment, not a reply".
 * The Comments contract treats a zero `commenter` as "no reply target".
 */
export const EMPTY_COMMENT_IDENTIFIER = {
  commenter: "0x0000000000000000000000000000000000000000" as Address,
  contractAddress: "0x0000000000000000000000000000000000000000" as Address,
  tokenId: 0n,
  nonce:
    "0x0000000000000000000000000000000000000000000000000000000000000000" as Hex,
} as const;

/**
 * Minimal ABI for posting a comment and reading the spark price. Mirrors
 * `packages/comments/abis/IComments.json`; kept inline to avoid pulling the
 * comments-contracts package (and a Foundry build) into the CLI, following the
 * same minimal-ABI convention used elsewhere in the CLI (e.g. buy.ts).
 */
export const commentsAbi = [
  {
    type: "function",
    name: "comment",
    stateMutability: "payable",
    inputs: [
      { name: "commenter", type: "address" },
      { name: "contractAddress", type: "address" },
      { name: "tokenId", type: "uint256" },
      { name: "text", type: "string" },
      {
        name: "replyTo",
        type: "tuple",
        components: [
          { name: "commenter", type: "address" },
          { name: "contractAddress", type: "address" },
          { name: "tokenId", type: "uint256" },
          { name: "nonce", type: "bytes32" },
        ],
      },
      { name: "commenterSmartWalletOwner", type: "address" },
      { name: "referrer", type: "address" },
    ],
    outputs: [
      {
        name: "",
        type: "tuple",
        components: [
          { name: "commenter", type: "address" },
          { name: "contractAddress", type: "address" },
          { name: "tokenId", type: "uint256" },
          { name: "nonce", type: "bytes32" },
        ],
      },
    ],
  },
  {
    type: "function",
    name: "sparkValue",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
  },
] as const;

/**
 * Minimal ABI for the coin reads the comment flow needs. The deployed Comments
 * contract only lets coin holders (or the owner/admin) comment, and owners
 * comment for free while everyone else includes one spark — so we need both
 * `isOwner` and `balanceOf`. Mirrors `ICoinComments`.
 */
export const coinCommentsAbi = [
  {
    type: "function",
    name: "isOwner",
    stateMutability: "view",
    inputs: [{ name: "", type: "address" }],
    outputs: [{ name: "", type: "bool" }],
  },
  {
    type: "function",
    name: "balanceOf",
    stateMutability: "view",
    inputs: [{ name: "", type: "address" }],
    outputs: [{ name: "", type: "uint256" }],
  },
] as const;
