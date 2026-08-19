import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

// The merged-list reader is backed by the coins-SDK; stub it to drive shapes.
vi.mock("@zoralabs/coins-sdk", () => ({ getCoinMergedComments: vi.fn() }));

import { getCoinMergedComments } from "@zoralabs/coins-sdk";
import { listCoinComments } from "./comments.js";

const COIN = "0x2bf7bd9c5609ffd0520d6f282713af2fc8dab914";

/* eslint-disable @typescript-eslint/no-explicit-any */
/** Set the mocked SDK call to return a merged-comments connection. */
function mockConnection(edges: unknown[], count: number, pageInfo = {}) {
  vi.mocked(getCoinMergedComments).mockResolvedValue({
    data: {
      zora20Token: {
        comments: {
          count,
          pageInfo: { hasNextPage: false, endCursor: null, ...pageInfo },
          edges,
        },
      },
    },
  } as any);
}
/* eslint-enable @typescript-eslint/no-explicit-any */

function call() {
  return listCoinComments({ chainId: 8453, address: COIN, first: 20 });
}

describe("listCoinComments", () => {
  beforeEach(() => vi.clearAllMocks());
  afterEach(() => vi.clearAllMocks());

  it("passes the coin identifiers through to the SDK", async () => {
    mockConnection([], 0);
    await listCoinComments({
      chainId: 8453,
      address: COIN,
      first: 50,
      after: "cursor-1",
    });
    expect(getCoinMergedComments).toHaveBeenCalledWith({
      address: COIN,
      chain: 8453,
      count: 50,
      after: "cursor-1",
    });
  });

  it("normalizes an on-chain GraphQLComment", async () => {
    mockConnection(
      [
        {
          node: {
            __typename: "GraphQLComment",
            commentId: "onchain-1",
            comment: "gm",
            timestamp: 1_700_000_000,
            userAddress: "0xabc",
            userProfile: { handle: "alice" },
            replies: { count: 2 },
          },
        },
      ],
      1,
    );

    const page = await call();
    expect(page.totalCount).toBe(1);
    expect(page.comments[0]).toEqual({
      commentId: "onchain-1",
      offChain: false,
      text: "gm",
      timestamp: 1_700_000_000,
      handle: "alice",
      authorAddress: "0xabc",
      // The merged feed omits spark counts on on-chain comments.
      sparkCount: 0,
      replyCount: 2,
    });
  });

  it("normalizes an off-chain comment, converting ISO time to unix seconds", async () => {
    mockConnection(
      [
        {
          node: {
            __typename: "GraphQLOffChainComment",
            commentId: "offchain-1",
            text: "welcome",
            commentedAt: "2023-11-14T22:13:20.000Z",
            sparkCount: 5,
            profile: { handle: "bob" },
            replies: { count: 4 },
          },
        },
      ],
      1,
    );

    const page = await call();
    expect(page.comments[0]).toEqual({
      commentId: "offchain-1",
      offChain: true,
      text: "welcome",
      timestamp: Math.floor(Date.parse("2023-11-14T22:13:20.000Z") / 1000),
      handle: "bob",
      sparkCount: 5,
      replyCount: 4,
    });
  });

  it("treats GraphQLBackfilledComment like an on-chain comment", async () => {
    mockConnection(
      [
        {
          node: {
            __typename: "GraphQLBackfilledComment",
            commentId: "bf-1",
            comment: "old one",
            timestamp: 1_600_000_000,
            userAddress: "0xdef",
            userProfile: null,
            replies: { count: 0 },
          },
        },
      ],
      1,
    );

    const page = await call();
    expect(page.comments[0]).toMatchObject({
      commentId: "bf-1",
      offChain: false,
      text: "old one",
      authorAddress: "0xdef",
      replyCount: 0,
    });
    expect(page.comments[0].handle).toBeUndefined();
  });

  it("exposes the next cursor only when there is a next page", async () => {
    mockConnection([], 0, { hasNextPage: true, endCursor: "cursor-2" });
    expect((await call()).nextCursor).toBe("cursor-2");

    mockConnection([], 0, { hasNextPage: false, endCursor: "cursor-2" });
    expect((await call()).nextCursor).toBeUndefined();
  });

  it("drops unknown union members", async () => {
    mockConnection(
      [
        { node: { __typename: "SomethingElse", commentId: "x" } },
        {
          node: {
            __typename: "GraphQLOffChainComment",
            commentId: "keep",
            text: "hi",
            commentedAt: "2023-11-14T22:13:20.000Z",
            sparkCount: 0,
            profile: null,
            replies: { count: 0 },
          },
        },
      ],
      2,
    );
    const page = await call();
    expect(page.comments).toHaveLength(1);
    expect(page.comments[0].commentId).toBe("keep");
  });

  // __typename is present at runtime but is NOT in the endpoint's typed
  // contract, so a contract-conformant response omitting it must still be
  // normalized (inferred from field shape) rather than dropping every comment.
  it("infers the source when __typename is absent", async () => {
    mockConnection(
      [
        {
          node: {
            commentId: "off-1",
            text: "hello",
            commentedAt: "2023-11-14T22:13:20.000Z",
            sparkCount: 2,
            profile: { handle: "carol" },
            replies: { count: 1 },
          },
        },
        {
          node: {
            commentId: "on-1",
            comment: "gm",
            timestamp: 1_700_000_000,
            userAddress: "0xabc",
            userProfile: { handle: "dave" },
            replies: { count: 0 },
          },
        },
      ],
      2,
    );
    const page = await call();
    expect(page.comments).toHaveLength(2);
    expect(page.comments[0]).toMatchObject({
      commentId: "off-1",
      offChain: true,
      text: "hello",
      handle: "carol",
    });
    expect(page.comments[1]).toMatchObject({
      commentId: "on-1",
      offChain: false,
      text: "gm",
      authorAddress: "0xabc",
      timestamp: 1_700_000_000,
    });
  });

  it("throws when the SDK returns an error", async () => {
    vi.mocked(getCoinMergedComments).mockResolvedValue({
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      error: { message: "boom" },
    } as any);
    await expect(call()).rejects.toThrow(/boom/);
  });
});
