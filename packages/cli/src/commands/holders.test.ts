import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { createProgram } from "../test/create-program.js";

vi.mock("@zoralabs/coins-sdk");
vi.mock("../lib/config.js", () => ({
  getApiKey: vi.fn(),
}));
vi.mock("../lib/render.js", () => ({
  renderOnce: vi.fn(),
  renderLive: vi.fn().mockResolvedValue(undefined),
}));
vi.mock("../lib/analytics.js");

import {
  getCoin,
  getCoinHolders,
  getProfile,
  setApiKey,
} from "@zoralabs/coins-sdk";
import { getApiKey } from "../lib/config.js";
import { renderOnce, renderLive } from "../lib/render.js";
import { getCommand } from "./get.jsx";

const makeCoinResponse = (name: string, address: string) => ({
  data: {
    zora20Token: {
      name,
      address,
      coinType: "CREATOR",
      marketCap: "5000000",
      marketCapDelta24h: "100000",
      volume24h: "250000",
      totalSupply: "1000000000",
      uniqueHolders: 62605,
      createdAt: "2026-01-01T00:00:00Z",
      creatorAddress: "0xcreator",
      creatorProfile: { handle: "jessepollak" },
    },
  },
});

const makeHoldersResponse = (
  edges: Array<{
    balance: string;
    ownerAddress: string;
    handle: string;
  }>,
  opts?: { count?: number; hasNextPage?: boolean; endCursor?: string },
) => ({
  data: {
    zora20Token: {
      tokenBalances: {
        count: opts?.count ?? edges.length,
        pageInfo: {
          hasNextPage: opts?.hasNextPage ?? false,
          endCursor: opts?.endCursor,
        },
        edges: edges.map((e) => ({
          node: {
            balance: e.balance,
            ownerAddress: e.ownerAddress,
            ownerProfile: {
              id: e.ownerAddress,
              handle: e.handle,
              platformBlocked: false,
            },
          },
        })),
      },
    },
  },
});

describe("get holders subcommand", () => {
  let logSpy: ReturnType<typeof vi.spyOn>;
  let errorSpy: ReturnType<typeof vi.spyOn>;
  let exitSpy: ReturnType<typeof vi.spyOn>;

  beforeEach(() => {
    logSpy = vi.spyOn(console, "log").mockImplementation(() => {});
    errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
    exitSpy = vi.spyOn(process, "exit").mockImplementation((code) => {
      throw new Error(`process.exit(${code})`);
    });
    vi.mocked(getApiKey).mockReturnValue(undefined);
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  it("renders static table with top holders", async () => {
    vi.mocked(getCoin).mockResolvedValue(
      makeCoinResponse("jessepollak", "0x1234") as any,
    );
    vi.mocked(getCoinHolders).mockResolvedValue(
      makeHoldersResponse(
        [
          {
            balance: "125000000000000000000000000",
            ownerAddress: "0xaaa",
            handle: "jessepollak",
          },
          {
            balance: "48200000000000000000000000",
            ownerAddress: "0xbbb",
            handle: "vitalik.eth",
          },
        ],
        { count: 62605 },
      ) as any,
    );

    const program = createProgram(getCommand);
    await program.parseAsync(["get", "holders", "--static", "0x1234"], {
      from: "user",
    });

    expect(renderOnce).toHaveBeenCalled();
  });

  it("renders live PaginatedTableView by default", async () => {
    vi.mocked(getCoin).mockResolvedValue(
      makeCoinResponse("jessepollak", "0x1234") as any,
    );
    vi.mocked(getCoinHolders).mockResolvedValue(
      makeHoldersResponse(
        [
          {
            balance: "125000000000000000000000000",
            ownerAddress: "0xaaa",
            handle: "jessepollak",
          },
        ],
        { count: 62605 },
      ) as any,
    );

    const program = createProgram(getCommand);
    await program.parseAsync(["get", "holders", "0x1234"], { from: "user" });

    expect(renderLive).toHaveBeenCalled();
  });

  it("outputs JSON when --json flag is set", async () => {
    vi.mocked(getCoin).mockResolvedValue(
      makeCoinResponse("jessepollak", "0x1234") as any,
    );
    vi.mocked(getCoinHolders).mockResolvedValue(
      makeHoldersResponse(
        [
          {
            balance: "125000000000000000000000000",
            ownerAddress: "0xaaa",
            handle: "jessepollak",
          },
        ],
        { count: 62605 },
      ) as any,
    );

    const program = createProgram(getCommand);
    await program.parseAsync(["get", "holders", "--json", "0x1234"], {
      from: "user",
    });

    expect(logSpy).toHaveBeenCalled();
    const output = JSON.parse(logSpy.mock.calls[0][0]);
    expect(output.coin).toBe("jessepollak");
    expect(output.totalHolders).toBe(62605);
    expect(output.holders).toHaveLength(1);
    expect(output.holders[0].handle).toBe("jessepollak");
    expect(output.holders[0].ownershipPercent).toBeCloseTo(12.5, 1);
  });

  it("exits with error for invalid --limit", async () => {
    const program = createProgram(getCommand);
    await expect(
      program.parseAsync(["get", "holders", "--limit", "21", "0x1234"], {
        from: "user",
      }),
    ).rejects.toThrow("process.exit(1)");

    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining("Invalid --limit"),
    );
  });

  it("exits with error for zero --limit", async () => {
    const program = createProgram(getCommand);
    await expect(
      program.parseAsync(["get", "holders", "--limit", "0", "0x1234"], {
        from: "user",
      }),
    ).rejects.toThrow("process.exit(1)");
  });

  it("passes limit and after to getCoinHolders", async () => {
    vi.mocked(getCoin).mockResolvedValue(
      makeCoinResponse("TestCoin", "0x1234") as any,
    );
    vi.mocked(getCoinHolders).mockResolvedValue(
      makeHoldersResponse([], { count: 0 }) as any,
    );

    const program = createProgram(getCommand);
    await program.parseAsync(
      [
        "get",
        "holders",
        "--static",
        "--limit",
        "20",
        "--after",
        "cursor123",
        "0x1234",
      ],
      { from: "user" },
    );

    expect(getCoinHolders).toHaveBeenCalledWith(
      expect.objectContaining({
        count: 20,
        after: "cursor123",
        address: "0x1234",
        chainId: 8453,
      }),
    );
  });

  it("includes nextCursor in JSON when there is a next page", async () => {
    vi.mocked(getCoin).mockResolvedValue(
      makeCoinResponse("TestCoin", "0x1234") as any,
    );
    vi.mocked(getCoinHolders).mockResolvedValue(
      makeHoldersResponse(
        [
          {
            balance: "1000000000000000000000",
            ownerAddress: "0xaaa",
            handle: "alice",
          },
        ],
        { count: 100, hasNextPage: true, endCursor: "abc123" },
      ) as any,
    );

    const program = createProgram(getCommand);
    await program.parseAsync(["get", "holders", "--json", "0x1234"], {
      from: "user",
    });

    const output = JSON.parse(logSpy.mock.calls[0][0]);
    expect(output.nextCursor).toBe("abc123");
  });

  it("sets API key when available", async () => {
    vi.mocked(getApiKey).mockReturnValue("test-key");
    vi.mocked(getCoin).mockResolvedValue(
      makeCoinResponse("TestCoin", "0x1234") as any,
    );
    vi.mocked(getCoinHolders).mockResolvedValue(
      makeHoldersResponse([], { count: 0 }) as any,
    );

    const program = createProgram(getCommand);
    await program.parseAsync(["get", "holders", "--static", "0x1234"], {
      from: "user",
    });

    expect(setApiKey).toHaveBeenCalledWith("test-key");
  });

  it("supports type prefix arguments", async () => {
    vi.mocked(getProfile).mockResolvedValue({
      data: {
        profile: {
          handle: "jessepollak",
          creatorCoin: { address: "0x1234" },
        },
      },
    } as any);
    vi.mocked(getCoin).mockResolvedValue(
      makeCoinResponse("jessepollak", "0x1234") as any,
    );
    vi.mocked(getCoinHolders).mockResolvedValue(
      makeHoldersResponse([], { count: 0 }) as any,
    );

    const program = createProgram(getCommand);
    await program.parseAsync(
      ["get", "holders", "--static", "creator-coin", "jessepollak"],
      { from: "user" },
    );

    expect(getProfile).toHaveBeenCalled();
  });
});
