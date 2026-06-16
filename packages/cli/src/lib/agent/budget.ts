import {
  type BudgetEntry,
  type BudgetPeriod,
  type BudgetState,
} from "../config.js";
import { fetchTokenPriceUsd } from "../wallet-balances.js";
import { WETH_ADDRESS } from "../constants.js";

const DAY_MS = 24 * 60 * 60 * 1000;

/** Tolerance so floating-point USD math doesn't reject a spend that lands exactly on the cap. */
const EPSILON = 1e-9;

/** Length of one budget window in ms, or `null` for `lifetime` (no window). */
export function periodMs(period: BudgetPeriod): number | null {
  switch (period) {
    case "daily":
      return DAY_MS;
    case "weekly":
      return 7 * DAY_MS;
    case "lifetime":
      return null;
  }
}

/**
 * The start of the budget's active window, rolling `windowStart` forward in
 * whole-period steps until it contains `now`. For `lifetime` the window never
 * moves (it covers all of history), so the stored `windowStart` is returned
 * unchanged. A malformed stored `windowStart` falls back to `now`.
 */
export function currentWindowStart(state: BudgetState, now: Date): string {
  const ms = periodMs(state.period);
  if (ms === null) return state.windowStart;
  let start = new Date(state.windowStart).getTime();
  if (!Number.isFinite(start)) start = now.getTime();
  const nowMs = now.getTime();
  while (start + ms <= nowMs) start += ms;
  return new Date(start).toISOString();
}

/**
 * USD already spent in the active window: the whole ledger for `lifetime`, or
 * just entries on/after the current window start for `daily`/`weekly`.
 */
export function spentInWindow(state: BudgetState, now: Date): number {
  if (state.period === "lifetime") {
    return state.ledger.reduce((sum, entry) => sum + entry.usd, 0);
  }
  const startMs = new Date(currentWindowStart(state, now)).getTime();
  return state.ledger
    .filter((entry) => new Date(entry.at).getTime() >= startMs)
    .reduce((sum, entry) => sum + entry.usd, 0);
}

export interface BudgetEvaluation {
  /** Whether a spend of the requested USD amount is within the budget. */
  allowed: boolean;
  /** The active cap, or `null` when there is no limit (unset or opted out). */
  limitUsd: number | null;
  /** USD already spent in the active window. */
  spent: number;
  /** USD left in the window, or `null` when there is no limit. */
  remaining: number | null;
  /** ISO start of the active window the evaluation used. */
  windowStart: string;
  /** Human-readable reason a spend is not allowed (only set when `allowed` is false). */
  reason?: string;
}

/**
 * Decide whether a `usd`-valued spend fits the budget right now. With no limit
 * (never configured, or an explicit opt-out) every spend is allowed and
 * `remaining` is `null`. This backs both `budget check` (the skills' pre-trade
 * gate) and `budget info`.
 */
export function evaluate(
  state: BudgetState,
  usd: number,
  now: Date,
): BudgetEvaluation {
  const windowStart = currentWindowStart(state, now);
  const spent = spentInWindow(state, now);

  if (state.optedOut || state.limitUsd === null) {
    return {
      allowed: true,
      limitUsd: state.limitUsd,
      spent,
      remaining: null,
      windowStart,
    };
  }

  const remaining = state.limitUsd - spent;
  const allowed = usd <= remaining + EPSILON;
  return {
    allowed,
    limitUsd: state.limitUsd,
    spent,
    remaining,
    windowStart,
    reason: allowed
      ? undefined
      : `A $${usd.toFixed(2)} spend would exceed the ${state.period} budget of ` +
        `$${state.limitUsd.toFixed(2)} ($${spent.toFixed(2)} already spent, ` +
        `$${Math.max(0, remaining).toFixed(2)} remaining).`,
  };
}

/**
 * Append a spend to the ledger, rolling `windowStart` forward first so the
 * stored window stays current. Returns a new state (does not mutate).
 */
export function appendSpend(
  state: BudgetState,
  entry: BudgetEntry,
  now: Date,
): BudgetState {
  return {
    ...state,
    windowStart: currentWindowStart(state, now),
    ledger: [...state.ledger, entry],
  };
}

/**
 * Convert an ETH amount to USD using the same on-chain price source the trading
 * commands use. Throws if the price can't be fetched, so a budget decision is
 * never made on a missing price.
 */
export async function usdFromEth(eth: number): Promise<number> {
  const priceUsd = await fetchTokenPriceUsd(WETH_ADDRESS);
  if (priceUsd === null) {
    throw new Error(
      "Could not fetch the ETH price to convert the amount to USD.",
    );
  }
  return eth * priceUsd;
}
