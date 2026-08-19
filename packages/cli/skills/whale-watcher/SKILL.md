---
name: whale-watcher
description: Watch top holders and large trades on chosen coins, then alert or react. On first invocation, collects which coins to watch, the definition of a "whale" (top-N holders and/or a minimum USD trade size), the actions to take (alert, auto-sell on a top-holder dump, auto-buy on a whale entry), and any spend/sell caps. Each subsequent invocation polls holders and recent trades per coin, detects whale activity, and alerts and/or acts per config.
compatibility: Requires the Zora CLI (@zoralabs/cli).
---

# Whale Watcher Skill

**Skill version 1.0.0**

## What This Skill Does

You are a Zora whale-watcher agent. Your job is to monitor the top holders and large trades on a chosen set of coins and, when whale activity appears, alert the operator and/or react with trades — per the configuration collected at setup. The skill runs **one iteration per invocation**: the first run collects config and snapshots the current top-holder set and latest trade per coin, and subsequent runs poll holders and recent trades, detect whale activity newer than the last-seen marker, and alert and/or act. To run on a schedule, use the agent's native scheduler (e.g. Claude Code's `/loop`; see the Skills guide at https://agents.zora.com/guides/agent-skills).

## Requirements

Before starting, make sure you have the Zora CLI basics — if they're not already in your context, use the core Zora CLI skill, installed alongside this one as `zora-cli` (how to invoke the CLI, response shapes, error handling). Commands below use `zora` as shorthand for `npx @zoralabs/cli@latest`. Always use `--json` and check for `error` in responses.

## Step 1: Determine mode

Check if `.whale-watcher-state.json` exists in the working directory.

- **File missing** → Setup Mode (Steps 2–4)
- **File exists** → ask the user what they want to do:
  - **Check** → Iteration Mode (Step 5)
  - **Add** / **Remove** / **Edit** watched coins or config → Manage Mode (Step 6)

---

## Setup Mode

### Step 2: Collect configuration

Ask the user:

1. **Coins to watch** — either an explicit list of coin addresses, or "my portfolio" (use the user's current holdings). For the portfolio option, run:

   ```bash
   zora balance coins --json
   ```

   and use the `coins` array (`address`, `name`). Prefer addresses over names throughout.

2. **Whale definition** — one or both of:
   - **Top-N holders** — treat the largest N holders as whales (suggest top 10). A change in this set (a new address entering the top N, or an existing top holder leaving) is a whale event.
   - **Minimum USD trade size** — treat any single trade whose `valueUsd` is at or above this threshold as a whale trade (suggest $1,000).

3. **Actions** — what to do when a whale event fires (default is **alert only**, the safest):
   - **Alert** — report the event to the operator. Always on.
   - **Auto-sell on dump** — when a large `SELL` from a top holder appears, sell part of the user's own position (gated: requires explicit opt-in).
   - **Auto-buy on entry** — when a large `BUY` (a whale entering) appears, buy into the coin (gated: requires explicit opt-in).

4. **Thresholds and caps** (only if any auto-action was enabled):
   - **Buy budget per event** — ETH amount per auto-buy (suggest 0.001 ETH default)
   - **Sell strategy per event** — sell all (`--all`) or a percentage (e.g. 50)
   - **Quote threshold** — preview trades above this size with `--quote` first (suggest >0.05 ETH)
   - **Max trades per iteration** (suggest 3)

### Step 3: Validate and snapshot

Verify the setup works and capture the baseline for each watched coin. Fail fast on any error.

```bash
zora wallet info --json
zora balance --json
```

Show the user their wallet address and ETH balance (from the `wallet` array, `symbol === "ETH"`).

For each watched coin, snapshot the current state:

```bash
zora get holders <address> --json
zora get trades <address> --limit 20 --json
```

- From holders, record the top-N holder addresses as `knownTopHolders`.
- From the `trades` array (returned **most-recent-first**, with fields `type` = `BUY`|`SELL`, `valueUsd`, `sender`, `senderHandle`, `coinAmount`, `transactionHash`, `timestamp`), record the newest trade's `timestamp` (or `transactionHash`) as `lastSeenTrade`. If there are no trades, use `null`.

### Step 4: Save state

Save `.whale-watcher-state.json`:

```json
{
  "coins": [
    {
      "address": "0x...",
      "name": "coin-name",
      "knownTopHolders": ["0x...", "0x..."],
      "lastSeenTrade": "<ISO timestamp or transactionHash or null>"
    }
  ],
  "config": {
    "topN": 10,
    "minTradeUsd": 1000,
    "alert": true,
    "autoSellOnDump": false,
    "autoBuyOnEntry": false,
    "buyBudgetEth": "0.001",
    "sellPercent": 100,
    "quoteThresholdEth": "0.05",
    "maxTradesPerIteration": 3
  },
  "createdAt": "<ISO timestamp>",
  "updatedAt": "<ISO timestamp>"
}
```

Show the watch list and config summary, then explain how to schedule the next iteration (see the Skills guide at https://agents.zora.com/guides/agent-skills). Stop.

---

## Iteration Mode

### Step 5: Poll, detect, and act

Read `.whale-watcher-state.json` to get `coins` and `config`.

For each watched coin (always use the `address`, never the name):

1. Fetch the current top holders:

   ```bash
   zora get holders <address> --json
   ```

   If this returns an `error`, log it and skip the coin this iteration — **never act on a stale or errored read**.

2. Fetch recent trades:

   ```bash
   zora get trades <address> --limit 20 --json
   ```

   The `trades` array is returned **most-recent-first** with fields `type` (`BUY`|`SELL`), `valueUsd`, `sender`, `senderHandle`, `coinAmount`, `transactionHash`, and `timestamp`. (Note: `get trades` has no per-trade coin address — the coin is the one you queried — and the USD field is `valueUsd`, not `amountUsd`.)

**Detect holder-set changes** (if `topN` is configured):

- Compute the current top-N holder addresses.
- Compare against `knownTopHolders`:
  - addresses in the current set but not in `knownTopHolders` → **whale entered**
  - addresses in `knownTopHolders` but not in the current set → **whale left**
- Record these as alert events.

**Detect large trades** (if `minTradeUsd` is configured):

- Walk trades and keep only those newer than `lastSeenTrade` (by `timestamp`; if `lastSeenTrade` is `null`, treat all as new). Stop at the first trade whose `transactionHash` equals `lastSeenTrade`.
- Of those, keep trades where `valueUsd >= minTradeUsd`. Reverse so they're processed oldest-first.
- A large `SELL` (`type === "SELL"`) whose `sender` is a current top holder is a **dump**; a large `BUY` (`type === "BUY"`) is a **whale entry**.

**Alert** (always): report each detected event — coin name, event type (entered / left / large BUY / large SELL), `valueUsd`, the address involved (the trade's `sender` for trade events, or the holder address for holder-set changes), and `transactionHash` where applicable.

**Act** (only the enabled, gated auto-actions; respect `maxTradesPerIteration` across all coins):

- **Auto-sell on dump** (only if `config.autoSellOnDump` is true) — on a large `SELL` from a top holder:
  1. Confirm the user holds the coin (from `zora balance --json`, `coins` array). Skip if not held.
  2. Log: `WHALE DUMP on <name> — selling per config (trade $<valueUsd>, tx <transactionHash>)`
  3. If the position exceeds `quoteThresholdEth`, preview first: `zora sell <address> --percent <sellPercent> --quote --json` (use `--all` if `sellPercent === 100`).
  4. Execute: `zora sell <address> --percent <sellPercent> --yes --json` (or `--all` if `sellPercent === 100`).
  5. Report coin name, amount sold, received, tx hash.

- **Auto-buy on entry** (only if `config.autoBuyOnEntry` is true) — on a large `BUY`:
  1. Check spendable ETH: `zora balance --json` (`wallet` array, `symbol === "ETH"`). Skip if too low.
  2. Log: `WHALE ENTRY on <name> — buying per config (trade $<valueUsd>, tx <transactionHash>)`
  3. Quote first if the budget exceeds `quoteThresholdEth`: `zora buy <address> --eth <buyBudgetEth> --quote --json`. Skip if the quote fails.
  4. Execute: `zora buy <address> --eth <buyBudgetEth> --yes --json`.
  5. Report coin name, amount received, tx hash.

After processing a coin, update its `knownTopHolders` to the current top-N set and its `lastSeenTrade` to the newest trade's `timestamp` (or `transactionHash`). Update top-level `updatedAt` and save state.

**If a trade fails:** do NOT advance `lastSeenTrade` past the failed event — the next iteration will re-detect it.

Report a summary: coins checked, holder changes detected, large trades detected, trades executed, trades skipped (reason), errors.

---

## Manage Mode

### Step 6: Add, remove, or edit the watch list and config

Read `.whale-watcher-state.json`, present the current watch list and config, and ask the user what to change:

- **Add** — same flow as Setup Step 2/3 for new coins: snapshot `knownTopHolders` and `lastSeenTrade`, then append to `coins`.
- **Remove** — ask which coin(s) to drop.
- **Edit** — update `config` fields (`topN`, `minTradeUsd`, actions, budget, caps). If `topN` changes, re-snapshot `knownTopHolders` for each coin so the next iteration compares against the right baseline.

Save the updated state and stop.

---

## Global Spending Budget

When `autoBuyOnEntry` is enabled, this skill places buys — and the agent may have a **global, wallet-level spending budget** (set with `zora agent budget set`) that caps total spend across _all_ skills. Honor it on every auto-buy:

**Before each auto-buy**, check the global budget with the buy's ETH amount:

```bash
zora agent budget check --eth <amount> --json
```

If the response is `"allowed": false`, **skip the buy**, log the `reason`, and stop buying for this iteration — the global cap is reached. When no budget is configured, `check` returns `"allowed": true`, so this is always safe to call. (Sells don't spend, so they aren't gated.)

The `zora buy` command automatically records the spend in the global budget ledger after a successful trade, so you do not need to call `budget record` separately.

## Safety Guards

- **Alert-by-default is the safest mode** — keep `autoSellOnDump` and `autoBuyOnEntry` off unless the user explicitly opts in during Setup or Manage Mode.
- **Never act on stale or errored reads** — if `zora get holders` or `zora get trades` returns an `error`, skip that coin this iteration.
- **Always quote before large trades** — preview with `--quote` for any trade above `config.quoteThresholdEth`; skip if the quote fails.
- **Respect caps** — never exceed `maxTradesPerIteration` across all coins, and honor the per-event budget/sell strategy.
- **Check spendable balance** before every auto-buy — stop buying if ETH runs low.
- **Prefer addresses over names** to avoid coin-type ambiguity.
- **Always log before trading** so the user can see what happened.
- **Don't advance the trade marker on a failed trade** so the event is retried next iteration.

## Resetting

Delete `.whale-watcher-state.json` to start fresh.
