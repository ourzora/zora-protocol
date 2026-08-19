import { describe, it, expect, vi, beforeEach } from "vitest";
import type { BudgetState } from "../config.js";
import {
  appendSpend,
  currentWindowStart,
  evaluate,
  periodMs,
  spentInWindow,
  usdFromEth,
} from "./budget.js";

vi.mock("../wallet-balances.js", () => ({
  fetchTokenPriceUsd: vi.fn(),
}));

import { fetchTokenPriceUsd } from "../wallet-balances.js";

const base = (overrides: Partial<BudgetState> = {}): BudgetState => ({
  version: 1,
  limitUsd: 100,
  period: "weekly",
  optedOut: false,
  windowStart: "2026-06-01T00:00:00.000Z",
  ledger: [],
  ...overrides,
});

describe("periodMs", () => {
  it("returns fixed windows for daily and weekly, null for lifetime", () => {
    expect(periodMs("daily")).toBe(86_400_000);
    expect(periodMs("weekly")).toBe(7 * 86_400_000);
    expect(periodMs("lifetime")).toBeNull();
  });
});

describe("currentWindowStart", () => {
  it("rolls a daily window forward to the day containing now", () => {
    const state = base({
      period: "daily",
      windowStart: "2026-06-01T00:00:00.000Z",
    });
    const now = new Date("2026-06-04T05:00:00.000Z");
    expect(currentWindowStart(state, now)).toBe("2026-06-04T00:00:00.000Z");
  });

  it("does not advance when now is inside the current window", () => {
    const state = base({
      period: "weekly",
      windowStart: "2026-06-01T00:00:00.000Z",
    });
    const now = new Date("2026-06-05T00:00:00.000Z");
    expect(currentWindowStart(state, now)).toBe("2026-06-01T00:00:00.000Z");
  });

  it("never moves a lifetime window", () => {
    const state = base({
      period: "lifetime",
      windowStart: "2020-01-01T00:00:00.000Z",
    });
    const now = new Date("2026-06-05T00:00:00.000Z");
    expect(currentWindowStart(state, now)).toBe("2020-01-01T00:00:00.000Z");
  });
});

describe("spentInWindow", () => {
  it("counts only entries on/after the active daily window", () => {
    const state = base({
      period: "daily",
      windowStart: "2026-06-01T00:00:00.000Z",
      ledger: [
        { usd: 10, skill: "dca", at: "2026-06-03T12:00:00.000Z" }, // previous day
        { usd: 25, skill: "dca", at: "2026-06-04T01:00:00.000Z" }, // today
        { usd: 5, skill: "trend-sniper", at: "2026-06-04T09:00:00.000Z" }, // today
      ],
    });
    const now = new Date("2026-06-04T10:00:00.000Z");
    expect(spentInWindow(state, now)).toBe(30);
  });

  it("sums the whole ledger for a lifetime budget", () => {
    const state = base({
      period: "lifetime",
      ledger: [
        { usd: 10, skill: "dca", at: "2024-01-01T00:00:00.000Z" },
        { usd: 40, skill: "dca", at: "2026-06-04T00:00:00.000Z" },
      ],
    });
    expect(spentInWindow(state, new Date("2026-06-04T10:00:00.000Z"))).toBe(50);
  });
});

describe("evaluate", () => {
  const now = new Date("2026-06-05T00:00:00.000Z");

  it("allows a spend under the cap and reports remaining", () => {
    const state = base({
      limitUsd: 100,
      ledger: [{ usd: 30, skill: "dca", at: "2026-06-02T00:00:00.000Z" }],
    });
    const result = evaluate(state, 50, now);
    expect(result.allowed).toBe(true);
    expect(result.spent).toBe(30);
    expect(result.remaining).toBe(70);
  });

  it("allows a spend that lands exactly on the cap", () => {
    const state = base({
      limitUsd: 100,
      ledger: [{ usd: 60, skill: "dca", at: "2026-06-02T00:00:00.000Z" }],
    });
    expect(evaluate(state, 40, now).allowed).toBe(true);
  });

  it("blocks a spend that would exceed the cap and explains why", () => {
    const state = base({
      limitUsd: 100,
      ledger: [{ usd: 80, skill: "dca", at: "2026-06-02T00:00:00.000Z" }],
    });
    const result = evaluate(state, 50, now);
    expect(result.allowed).toBe(false);
    expect(result.reason).toContain("would exceed");
  });

  it("always allows when opted out, with no remaining", () => {
    const state = base({ optedOut: true, limitUsd: null });
    const result = evaluate(state, 9999, now);
    expect(result.allowed).toBe(true);
    expect(result.remaining).toBeNull();
  });
});

describe("appendSpend", () => {
  it("adds an entry and rolls the window forward without mutating input", () => {
    const state = base({
      period: "daily",
      windowStart: "2026-06-01T00:00:00.000Z",
    });
    const now = new Date("2026-06-04T08:00:00.000Z");
    const updated = appendSpend(
      state,
      { usd: 12, skill: "dca", at: now.toISOString() },
      now,
    );
    expect(state.ledger).toHaveLength(0); // original untouched
    expect(updated.ledger).toHaveLength(1);
    expect(updated.windowStart).toBe("2026-06-04T00:00:00.000Z");
  });
});

describe("usdFromEth", () => {
  beforeEach(() => vi.clearAllMocks());

  it("multiplies the ETH amount by the fetched price", async () => {
    vi.mocked(fetchTokenPriceUsd).mockResolvedValue(3000);
    await expect(usdFromEth(0.01)).resolves.toBeCloseTo(30);
  });

  it("throws when the price can't be fetched", async () => {
    vi.mocked(fetchTokenPriceUsd).mockResolvedValue(null);
    await expect(usdFromEth(0.01)).rejects.toThrow(/ETH price/);
  });
});
