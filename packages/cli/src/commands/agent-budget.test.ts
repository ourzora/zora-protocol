import { describe, it, expect, vi, beforeEach } from "vitest";
import { createProgram } from "../test/create-program.js";
import { agentCommand } from "./agent.js";
import type { BudgetState } from "../lib/config.js";

// In-memory budget store so the command tests stay off the filesystem. The
// window/ledger math itself is covered by lib/agent/budget.test.ts.
let store: BudgetState | undefined;

vi.mock("../lib/config.js", () => ({
  getBudget: vi.fn(() => store),
  saveBudget: vi.fn((s: Omit<BudgetState, "version">) => {
    store = { ...s, version: 1 };
  }),
  clearBudget: vi.fn(() => {
    store = undefined;
  }),
  getBudgetPath: vi.fn(() => "/home/u/.config/zora/budget.json"),
}));

vi.mock("../lib/wallet-balances.js", () => ({
  fetchTokenPriceUsd: vi.fn(async () => 3000),
}));

import { fetchTokenPriceUsd } from "../lib/wallet-balances.js";

vi.mock("../lib/analytics.js", () => ({ track: vi.fn() }));
vi.mock("@inquirer/confirm", () => ({ default: vi.fn(async () => true) }));

import confirm from "@inquirer/confirm";

function runBudget(args: string[]) {
  const program = createProgram(agentCommand);
  return program.parseAsync(["agent", "budget", ...args], { from: "user" });
}

function captureLog() {
  const calls: string[] = [];
  const spy = vi.spyOn(console, "log").mockImplementation((...args) => {
    calls.push(args.join(" "));
  });
  return { output: () => calls.join("\n"), restore: () => spy.mockRestore() };
}

describe("agent budget", () => {
  beforeEach(() => {
    store = undefined;
    vi.clearAllMocks();
  });

  describe("set", () => {
    it("stores a USD limit and period", async () => {
      const log = captureLog();
      await runBudget(["set", "250", "--period", "weekly", "--json"]);
      const parsed = JSON.parse(log.output());
      log.restore();
      expect(parsed).toMatchObject({
        limitUsd: 250,
        period: "weekly",
        optedOut: false,
      });
      expect(store).toMatchObject({
        limitUsd: 250,
        period: "weekly",
        optedOut: false,
        ledger: [],
      });
    });

    it("defaults the period to weekly", async () => {
      const log = captureLog();
      await runBudget(["set", "100", "--json"]);
      log.restore();
      expect(store?.period).toBe("weekly");
    });

    it("opts out with --no-limit", async () => {
      const log = captureLog();
      await runBudget(["set", "--no-limit", "--json"]);
      const parsed = JSON.parse(log.output());
      log.restore();
      expect(parsed).toMatchObject({ limitUsd: null, optedOut: true });
      expect(store).toMatchObject({ limitUsd: null, optedOut: true });
    });

    it("rejects an amount together with --no-limit", async () => {
      const log = captureLog();
      await expect(
        runBudget(["set", "250", "--no-limit", "--json"]),
      ).rejects.toThrow();
      const parsed = JSON.parse(log.output());
      log.restore();
      expect(parsed.error).toMatch(/not both/);
    });

    it("rejects a non-positive amount", async () => {
      const log = captureLog();
      await expect(runBudget(["set", "0", "--json"])).rejects.toThrow();
      const parsed = JSON.parse(log.output());
      log.restore();
      expect(parsed.error).toMatch(/Invalid budget amount/);
    });

    it("preserves the existing ledger when adjusting the cap", async () => {
      store = {
        version: 1,
        limitUsd: 100,
        period: "weekly",
        optedOut: false,
        windowStart: "2026-06-01T00:00:00.000Z",
        ledger: [{ usd: 20, skill: "dca", at: "2026-06-02T00:00:00.000Z" }],
      };
      const log = captureLog();
      await runBudget(["set", "300", "--json"]);
      log.restore();
      expect(store?.limitUsd).toBe(300);
      expect(store?.ledger).toHaveLength(1);
      expect(store?.windowStart).toBe("2026-06-01T00:00:00.000Z");
    });
  });

  describe("info", () => {
    it("reports nothing configured when no budget exists", async () => {
      const log = captureLog();
      await runBudget(["info", "--json"]);
      const parsed = JSON.parse(log.output());
      log.restore();
      expect(parsed).toMatchObject({ configured: false });
    });

    it("reports spent and remaining for a configured budget", async () => {
      store = {
        version: 1,
        limitUsd: 100,
        period: "lifetime",
        optedOut: false,
        windowStart: "2026-06-01T00:00:00.000Z",
        ledger: [{ usd: 30, skill: "dca", at: "2026-06-02T00:00:00.000Z" }],
      };
      const log = captureLog();
      await runBudget(["info", "--json"]);
      const parsed = JSON.parse(log.output());
      log.restore();
      expect(parsed).toMatchObject({
        configured: true,
        limitUsd: 100,
        spent: 30,
        remaining: 70,
        entries: 1,
      });
    });

    it("reports no limit and null remaining when opted out", async () => {
      store = {
        version: 1,
        limitUsd: null,
        period: "weekly",
        optedOut: true,
        windowStart: "2026-06-01T00:00:00.000Z",
        ledger: [],
      };
      const log = captureLog();
      await runBudget(["info", "--json"]);
      const parsed = JSON.parse(log.output());
      log.restore();
      expect(parsed).toMatchObject({
        configured: true,
        optedOut: true,
        limitUsd: null,
        remaining: null,
      });
    });
  });

  describe("check", () => {
    it("allows everything when no budget is configured", async () => {
      const log = captureLog();
      await runBudget(["check", "--usd", "9999", "--json"]);
      const parsed = JSON.parse(log.output());
      log.restore();
      expect(parsed).toMatchObject({ allowed: true, configured: false });
    });

    it("allows --eth with no budget without fetching the ETH price", async () => {
      const log = captureLog();
      await runBudget(["check", "--eth", "0.05", "--json"]);
      const parsed = JSON.parse(log.output());
      log.restore();
      expect(parsed).toMatchObject({ allowed: true, configured: false });
      // The no-budget guard must run before amount resolution, so a price-feed
      // outage can never break the unconditional pre-trade check.
      expect(fetchTokenPriceUsd).not.toHaveBeenCalled();
    });

    it("allows a spend under the cap", async () => {
      store = {
        version: 1,
        limitUsd: 100,
        period: "weekly",
        optedOut: false,
        windowStart: "2026-06-01T00:00:00.000Z",
        ledger: [],
      };
      const log = captureLog();
      await runBudget(["check", "--usd", "40", "--json"]);
      const parsed = JSON.parse(log.output());
      log.restore();
      expect(parsed).toMatchObject({ allowed: true });
    });

    it("blocks a spend over the cap", async () => {
      // Lifetime so the recorded spend always counts regardless of when the
      // test runs (a windowed period could roll past an old ledger entry).
      store = {
        version: 1,
        limitUsd: 100,
        period: "lifetime",
        optedOut: false,
        windowStart: "2026-06-01T00:00:00.000Z",
        ledger: [{ usd: 80, skill: "dca", at: "2026-06-02T00:00:00.000Z" }],
      };
      const log = captureLog();
      await runBudget(["check", "--usd", "40", "--json"]);
      const parsed = JSON.parse(log.output());
      log.restore();
      expect(parsed.allowed).toBe(false);
      expect(parsed.reason).toMatch(/exceed/);
    });

    it("converts an --eth amount to USD before checking", async () => {
      store = {
        version: 1,
        limitUsd: 100,
        period: "weekly",
        optedOut: false,
        windowStart: "2026-06-01T00:00:00.000Z",
        ledger: [],
      };
      const log = captureLog();
      // 0.05 ETH * $3000 = $150 > $100 cap
      await runBudget(["check", "--eth", "0.05", "--json"]);
      const parsed = JSON.parse(log.output());
      log.restore();
      expect(parsed.usd).toBeCloseTo(150);
      expect(parsed.allowed).toBe(false);
    });

    it("allows any spend when opted out", async () => {
      store = {
        version: 1,
        limitUsd: null,
        period: "weekly",
        optedOut: true,
        windowStart: "2026-06-01T00:00:00.000Z",
        ledger: [],
      };
      const log = captureLog();
      await runBudget(["check", "--usd", "100000", "--json"]);
      const parsed = JSON.parse(log.output());
      log.restore();
      expect(parsed).toMatchObject({
        allowed: true,
        configured: true,
        optedOut: true,
        limitUsd: null,
        remaining: null,
      });
    });

    it("allows --eth when opted out without fetching the ETH price", async () => {
      store = {
        version: 1,
        limitUsd: null,
        period: "weekly",
        optedOut: true,
        windowStart: "2026-06-01T00:00:00.000Z",
        ledger: [],
      };
      const log = captureLog();
      await runBudget(["check", "--eth", "0.05", "--json"]);
      const parsed = JSON.parse(log.output());
      log.restore();
      expect(parsed).toMatchObject({ allowed: true, configured: true, optedOut: true });
      // The opted-out guard must run before amount resolution, so a price-feed
      // outage can never break the unconditional pre-trade check.
      expect(fetchTokenPriceUsd).not.toHaveBeenCalled();
    });

    it("rejects passing both --usd and --eth", async () => {
      // Amount validation runs only once a budget is configured (the no-budget
      // guard short-circuits first), so configure one to reach it.
      store = {
        version: 1,
        limitUsd: 100,
        period: "weekly",
        optedOut: false,
        windowStart: "2026-06-01T00:00:00.000Z",
        ledger: [],
      };
      const log = captureLog();
      await expect(
        runBudget(["check", "--usd", "10", "--eth", "0.01", "--json"]),
      ).rejects.toThrow();
      const parsed = JSON.parse(log.output());
      log.restore();
      expect(parsed.error).toMatch(/exactly one/);
    });
  });

  describe("record", () => {
    it("appends a spend to the ledger", async () => {
      store = {
        version: 1,
        limitUsd: 100,
        period: "weekly",
        optedOut: false,
        windowStart: "2026-06-01T00:00:00.000Z",
        ledger: [],
      };
      const log = captureLog();
      await runBudget([
        "record",
        "--usd",
        "30",
        "--skill",
        "dca",
        "--tx",
        "0xabc",
        "--json",
      ]);
      const parsed = JSON.parse(log.output());
      log.restore();
      expect(store?.ledger).toHaveLength(1);
      expect(store?.ledger[0]).toMatchObject({
        usd: 30,
        skill: "dca",
        txHash: "0xabc",
      });
      expect(parsed).toMatchObject({ spent: 30, remaining: 70 });
    });

    it("succeeds as a no-op when no budget is configured (safe to call unconditionally)", async () => {
      const log = captureLog();
      // Must not throw — skills call `record` after every trade, including
      // before a budget is ever set.
      await runBudget(["record", "--usd", "30", "--skill", "dca", "--json"]);
      const parsed = JSON.parse(log.output());
      log.restore();
      expect(parsed).toMatchObject({ recorded: false, configured: false });
      expect(store).toBeUndefined();
    });

    it("no-ops on --eth with no budget without fetching the ETH price", async () => {
      const log = captureLog();
      await runBudget(["record", "--eth", "0.05", "--skill", "dca", "--json"]);
      const parsed = JSON.parse(log.output());
      log.restore();
      expect(parsed).toMatchObject({ recorded: false, configured: false });
      expect(fetchTokenPriceUsd).not.toHaveBeenCalled();
    });

    it("skips recording when opted out (no tracking for unlimited budgets)", async () => {
      store = {
        version: 1,
        limitUsd: null,
        period: "weekly",
        optedOut: true,
        windowStart: "2026-06-01T00:00:00.000Z",
        ledger: [],
      };
      const log = captureLog();
      await runBudget(["record", "--usd", "30", "--skill", "dca", "--json"]);
      const parsed = JSON.parse(log.output());
      log.restore();
      expect(store?.ledger).toHaveLength(0);
      expect(parsed).toMatchObject({ recorded: false, configured: true, optedOut: true });
    });
  });

  describe("reset", () => {
    it("clears spend but keeps the cap", async () => {
      store = {
        version: 1,
        limitUsd: 100,
        period: "weekly",
        optedOut: false,
        windowStart: "2026-06-01T00:00:00.000Z",
        ledger: [{ usd: 30, skill: "dca", at: "2026-06-02T00:00:00.000Z" }],
      };
      const log = captureLog();
      await runBudget(["reset", "--yes", "--json"]);
      const parsed = JSON.parse(log.output());
      log.restore();
      expect(parsed).toMatchObject({ reset: true, cleared: false });
      expect(store?.limitUsd).toBe(100);
      expect(store?.ledger).toHaveLength(0);
    });

    it("removes the budget entirely with --clear", async () => {
      store = {
        version: 1,
        limitUsd: 100,
        period: "weekly",
        optedOut: false,
        windowStart: "2026-06-01T00:00:00.000Z",
        ledger: [],
      };
      const log = captureLog();
      await runBudget(["reset", "--clear", "--yes", "--json"]);
      log.restore();
      expect(store).toBeUndefined();
    });

    it("prompts for confirmation in interactive mode", async () => {
      store = {
        version: 1,
        limitUsd: 100,
        period: "weekly",
        optedOut: false,
        windowStart: "2026-06-01T00:00:00.000Z",
        ledger: [{ usd: 30, skill: "dca", at: "2026-06-02T00:00:00.000Z" }],
      };
      const log = captureLog();
      await runBudget(["reset"]);
      log.restore();
      expect(confirm).toHaveBeenCalled();
      expect(store?.ledger).toHaveLength(0);
    });
  });
});
