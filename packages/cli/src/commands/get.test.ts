import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { createProgram } from "../test/create-program.js";

vi.mock("@zoralabs/coins-sdk", () => ({
  setApiKey: vi.fn(),
  getCoin: vi.fn(),
  getProfile: vi.fn(),
}));

vi.mock("../lib/config.js", () => ({
  getApiKey: vi.fn(),
}));

vi.mock("../lib/render.js", () => ({
  renderOnce: vi.fn(),
}));

import { setApiKey, getCoin, getProfile } from "@zoralabs/coins-sdk";
import { getApiKey } from "../lib/config.js";
import { getCommand } from "./get.jsx";

describe("getCommand", () => {
  let logSpy: ReturnType<typeof vi.spyOn>;
  let exitSpy: ReturnType<typeof vi.spyOn>;

  beforeEach(() => {
    logSpy = vi.spyOn(console, "log").mockImplementation(() => {});
    vi.spyOn(console, "error").mockImplementation(() => {});
    exitSpy = vi.spyOn(process, "exit").mockImplementation((code) => {
      throw new Error(`exit ${code}`);
    });
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  function parseJson(...args: string[]) {
    const program = createProgram(getCommand);
    return program.parseAsync(["get", ...args, "--json"], { from: "user" });
  }

  function parsedOutput(): unknown {
    return JSON.parse(logSpy.mock.calls.map((c) => c[0]).join("\n"));
  }

  it("exits with error for invalid --type", async () => {
    await expect(parseJson("something", "--type", "banana")).rejects.toThrow(
      "exit 1",
    );
    expect(logSpy).toHaveBeenCalledWith(
      expect.stringContaining("Invalid --type"),
    );
  });

  it("exits with error for --type trend", async () => {
    await expect(parseJson("geese", "--type", "trend")).rejects.toThrow(
      "exit 1",
    );
    expect(logSpy).toHaveBeenCalledWith(
      expect.stringContaining("Trend name lookup is not yet supported"),
    );
  });

  it("exits with error for --type post", async () => {
    await expect(parseJson("something", "--type", "post")).rejects.toThrow(
      "exit 1",
    );
    expect(logSpy).toHaveBeenCalledWith(
      expect.stringContaining("Posts can only be looked up by address"),
    );
  });

  it("outputs coin JSON for address lookup", async () => {
    vi.mocked(getApiKey).mockReturnValue("test-key");
    vi.mocked(getCoin).mockResolvedValue({
      data: {
        zora20Token: {
          name: "TestCoin",
          address: "0x1234",
          coinType: "CONTENT",
          marketCap: "5000000",
          marketCapDelta24h: "100000",
          volume24h: "250000",
          uniqueHolders: 1842,
          createdAt: "2026-03-01T14:30:00Z",
        },
      },
    } as any);

    await parseJson("0x1234");

    expect(setApiKey).toHaveBeenCalledWith("test-key");
    expect(getCoin).toHaveBeenCalledWith({ address: "0x1234" });
    expect(parsedOutput()).toMatchObject({
      name: "TestCoin",
      address: "0x1234",
      coinType: "post",
      marketCap: "5000000",
      volume24h: "250000",
      uniqueHolders: 1842,
      createdAt: "2026-03-01T14:30:00Z",
    });
    expect(exitSpy).not.toHaveBeenCalled();
  });

  it("exits with error for not-found coin", async () => {
    vi.mocked(getApiKey).mockReturnValue(undefined as any);
    vi.mocked(getCoin).mockResolvedValue({
      data: { zora20Token: undefined },
    } as any);

    await expect(parseJson("0xdead")).rejects.toThrow("exit 1");
    expect(logSpy).toHaveBeenCalledWith(
      expect.stringContaining("No coin found"),
    );
  });

  it("exits with error when SDK call throws", async () => {
    vi.mocked(getApiKey).mockReturnValue("test-key");
    vi.mocked(getCoin).mockRejectedValue(new Error("Network error"));

    await expect(parseJson("0x1234")).rejects.toThrow("exit 1");
    expect(logSpy).toHaveBeenCalledWith(
      expect.stringContaining("Network error"),
    );
  });

  it("does not call setApiKey when no key configured", async () => {
    vi.mocked(getApiKey).mockReturnValue(undefined as any);
    vi.mocked(getCoin).mockResolvedValue({
      data: {
        zora20Token: { name: "NoKeyCoin", address: "0xabc", marketCap: "100" },
      },
    } as any);
    vi.mocked(setApiKey).mockClear();

    await parseJson("0xabc");

    expect(setApiKey).not.toHaveBeenCalled();
    expect(parsedOutput()).toMatchObject({ name: "NoKeyCoin" });
  });

  it("resolves creator-coin by name with --type", async () => {
    vi.mocked(getApiKey).mockReturnValue(undefined as any);
    vi.mocked(getProfile).mockResolvedValue({
      data: {
        profile: { handle: "jacob", creatorCoin: { address: "0xcoin" } },
      },
    } as any);
    vi.mocked(getCoin).mockResolvedValue({
      data: {
        zora20Token: {
          name: "jacob",
          address: "0xcoin",
          coinType: "CREATOR",
          marketCap: "8100000",
          marketCapDelta24h: "-280000",
          volume24h: "1200000",
          uniqueHolders: 12304,
          createdAt: "2026-01-20T11:15:00Z",
        },
      },
    } as any);

    await parseJson("jacob", "--type", "creator-coin");

    expect(getProfile).toHaveBeenCalledWith({ identifier: "jacob" });
    expect(getCoin).toHaveBeenCalledWith({ address: "0xcoin" });
    expect(parsedOutput()).toMatchObject({
      name: "jacob",
      coinType: "creator-coin",
    });
  });

  it("exits with error when --type mismatches coin type", async () => {
    vi.mocked(getApiKey).mockReturnValue(undefined as any);
    vi.mocked(getCoin).mockResolvedValue({
      data: {
        zora20Token: {
          name: "CreatorCoin",
          address: "0x1234",
          coinType: "CREATOR",
          marketCap: "100",
        },
      },
    } as any);

    await expect(parseJson("0x1234", "--type", "post")).rejects.toThrow(
      "exit 1",
    );
    const output = logSpy.mock.calls.map((c) => c[0]).join("\n");
    expect(output).toContain("is a creator-coin, not a post");
    expect(output).toContain("zora get 0x1234 --type creator-coin");
  });

  it("allows --type trend with address", async () => {
    vi.mocked(getApiKey).mockReturnValue(undefined as any);
    vi.mocked(getCoin).mockResolvedValue({
      data: {
        zora20Token: {
          name: "SomeTrend",
          address: "0xtrend",
          coinType: "TREND",
          marketCap: "200",
        },
      },
    } as any);

    await parseJson("0xtrend", "--type", "trend");

    expect(getCoin).toHaveBeenCalledWith({ address: "0xtrend" });
    expect(parsedOutput()).toMatchObject({
      name: "SomeTrend",
      coinType: "trend",
    });
  });

  it("allows --type post with address", async () => {
    vi.mocked(getApiKey).mockReturnValue(undefined as any);
    vi.mocked(getCoin).mockResolvedValue({
      data: {
        zora20Token: {
          name: "SomePost",
          address: "0xpost",
          coinType: "CONTENT",
          marketCap: "100",
        },
      },
    } as any);

    await parseJson("0xpost", "--type", "post");

    expect(getCoin).toHaveBeenCalledWith({ address: "0xpost" });
    expect(parsedOutput()).toMatchObject({ name: "SomePost" });
  });

  it("resolves bare name as creator-coin lookup", async () => {
    vi.mocked(getApiKey).mockReturnValue(undefined as any);
    vi.mocked(getProfile).mockResolvedValue({
      data: {
        profile: { handle: "alice", creatorCoin: { address: "0xalice" } },
      },
    } as any);
    vi.mocked(getCoin).mockResolvedValue({
      data: {
        zora20Token: {
          name: "alice",
          address: "0xalice",
          coinType: "CREATOR",
          marketCap: "1000000",
        },
      },
    } as any);

    await parseJson("alice");

    expect(getProfile).toHaveBeenCalledWith({ identifier: "alice" });
    expect(parsedOutput()).toMatchObject({ name: "alice" });
  });
});
