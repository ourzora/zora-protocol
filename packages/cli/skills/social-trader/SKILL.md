---
name: social-trader
description: Track specific creators and trade on their activity. On first invocation, collects a list of creators to follow, a budget per buy, the triggers to act on (new post coins and/or creator-coin market-cap growth), and spend caps. Each subsequent invocation polls each creator and buys when a trigger fires.
compatibility: Requires the Zora CLI (@zoralabs/cli).
---

# Social Trader Skill

**Skill version 1.0.0**

## What This Skill Does

You are a Zora social-trading agent. This skill follows a set of creators and trades on their onchain activity — buying a creator's newly published post coins, and/or buying a creator's coin when its market cap is growing past a threshold. It runs **one iteration per invocation**: on the first run it collects config and snapshots each creator's current state, and on subsequent runs it polls each followed creator for new qualifying activity and buys when a trigger fires. To run on a schedule, use the agent's native scheduler (e.g. Claude Code's `/loop`; see the Skills guide at https://agents.zora.com/guides/agent-skills).

## Requirements

Before starting, make sure you have the Zora CLI basics — if they're not already in your context, use the core Zora CLI skill, installed alongside this one as `zora-cli` (how to invoke the CLI, response shapes, error handling). Commands below use `zora` as shorthand for `npx @zoralabs/cli@latest`. Always use `--json` and check for `"error"` in responses.

## Step 1: Determine mode

Check if `.social-trader-state.json` exists in the working directory.

- **File missing** → Setup Mode (Steps 2–4)
- **File exists** → ask the user what they want to do:
  - **Check** → Iteration Mode (Step 5)
  - **Add** / **Remove** / **Edit** creators or config → Manage Mode (Step 6)

---

## Setup Mode

### Step 2: Collect configuration

Ask the user:

1. **Creators to follow** — one or more Zora handles (or wallet addresses).
2. **Budget per buy** — ETH amount per buy (suggest 0.001 ETH default). Note whether to spend in ETH or USD (`--eth` vs `--usd`).
3. **Triggers** — which signals to act on (one or both):
   - **New post coin** — buy a creator's NEW post coin when they publish one.
   - **Creator-coin growth** — buy a creator's coin when its market cap grows past a threshold (ask for the threshold: a percentage increase since last seen, e.g. 20, and/or an absolute market-cap floor).
4. **Spend caps**:
   - **Per-iteration cap** — max ETH (or USD) to spend in a single iteration.
   - **Total cap** — max ETH (or USD) to spend across the whole run.
5. **Follow creators?** (optional) — after buying a creator's **creator coin**, also follow them on Zora. This is **free**: you'll already hold their creator coin, which is the coin `zora follow` gates on. Default: no. It does not apply to post-coin buys — those don't grant the creator coin.

### Step 3: Validate and snapshot

Run these to verify the setup works and capture a starting point:

```bash
zora wallet info --json
zora balance --json
```

Show the user their wallet address and ETH balance (from the `wallet` array, the entry where `symbol === "ETH"`). Fail fast on any error.

For **each** creator, snapshot the current state so Iteration Mode knows the baseline:

```bash
zora profile <handle> --json                 # overview
zora profile posts <handle> --json --limit 20 # most recent post coins
```

Record, per creator:

- `lastSeenPostAddress` — the `address` of the newest entry in the `posts` array (or `null` if none), and `lastSeenPostTimestamp` — its `createdAt`. This is the marker for detecting NEW post coins.
- `lastCreatorCoinMarketCap` — the creator coin's current market cap. Get it from `zora get creator-coin <handle> --json` (read `marketCap`), or fall back to the overview. `null` if the creator has no coin.

### Step 4: Save state

Write `.social-trader-state.json`:

```json
{
  "config": {
    "budget": "0.001",
    "spendToken": "eth",
    "triggers": {
      "newPostCoin": true,
      "creatorCoinGrowth": true,
      "growthPercent": 20,
      "marketCapFloor": null
    },
    "perIterationCap": "0.01",
    "totalCap": "0.1",
    "followCreators": false
  },
  "creators": [
    {
      "handle": "<handle-or-address>",
      "lastSeenPostAddress": "0x...",
      "lastSeenPostTimestamp": "<ISO timestamp or null>",
      "lastCreatorCoinMarketCap": 50000
    }
  ],
  "spend": {
    "spentToday": "0",
    "spentTotal": "0",
    "spendDate": "<YYYY-MM-DD>"
  },
  "createdAt": "<ISO timestamp>",
  "updatedAt": "<ISO timestamp>"
}
```

Tell the user setup is complete, summarize the followed creators and triggers, and explain how to schedule the next iteration (see the Skills guide at https://agents.zora.com/guides/agent-skills). Stop.

---

## Iteration Mode

### Step 5: Poll each creator and execute buys

Read `.social-trader-state.json` to get `config`, `creators`, and `spend`.

**Reset the daily counter first.** If `spend.spendDate` is not today's date, set `spentToday` to `0` and `spendDate` to today.

Track `spentThisIteration` locally, starting at `0`. Before any buy, confirm it stays within all caps:

- `spentThisIteration + budget <= perIterationCap`
- `spentTotal + budget <= totalCap`

If a buy would breach a cap, skip it and note the reason in the report.

For **each** creator in `creators`:

1. Fetch the overview: `zora profile <handle> --json`. If it errors, log and skip this creator (don't act on a failed read).

2. **New post coin trigger** (if `config.triggers.newPostCoin`):
   1. `zora profile posts <handle> --json --limit 20` (most-recent-first).
   2. Walk the `posts` array from newest and collect entries where `createdAt > lastSeenPostTimestamp` (or, if timestamps are unavailable, entries appearing before the saved `lastSeenPostAddress`). These are the NEW post coins.
   3. For each new post coin (process oldest-first, max 2 new coins per creator per iteration):
      - Verify the entry has an `address`; **prefer the address over the name** for all subsequent commands.
      - Skip if its `marketCap` is below `marketCapFloor` (when set).
      - Quote: `zora buy <address> --eth <budget> --quote --json`. Skip on quote error.
      - If within caps, execute: `zora buy <address> --eth <budget> --yes --json` (use `--usd <budget>` if `spendToken === "usd"`).
      - On success, add `budget` to `spentThisIteration`, `spentToday`, and `spentTotal`. Report creator, coin name, our amount received, tx hash.
   4. After processing, update this creator's `lastSeenPostAddress` and `lastSeenPostTimestamp` to the newest post coin seen (whether or not it was bought).

3. **Creator-coin growth trigger** (if `config.triggers.creatorCoinGrowth`):
   1. Fetch current market cap: `zora get creator-coin <handle> --json` → read `marketCap`. Skip on error.
   2. If `lastCreatorCoinMarketCap` is set, compute growth: `(current - lastCreatorCoinMarketCap) / lastCreatorCoinMarketCap * 100`.
   3. **Trigger if** growth `>= config.triggers.growthPercent` AND (`marketCapFloor` is null OR `current >= marketCapFloor`):
      - Log: `GROWTH triggered for <handle> creator coin (market cap: $<current>, up <growth>% since $<lastCreatorCoinMarketCap>)`.
      - Get the creator-coin address from the `zora get creator-coin <handle> --json` response and use it for the buy.
      - Quote: `zora buy <address> --eth <budget> --quote --json`. Skip on quote error.
      - If within caps, execute: `zora buy <address> --eth <budget> --yes --json`.
      - On success, add `budget` to the spend counters. Report creator, amount received, tx hash.
      - **Follow (if `config.followCreators`):** you now hold this creator's creator coin, so following them is free. Run `zora follow <handle> --json` (it's a no-op if you already follow them; ignore an "already following" result). Skip this when `followCreators` is false. Note: only the creator-coin buy above grants the coin — do **not** follow after a post-coin buy in the new-post-coin trigger.
   4. Update `lastCreatorCoinMarketCap` to `current` regardless of whether a buy fired, so the next iteration measures growth from the latest baseline.

After processing all creators, set `spend.spentToday` / `spentTotal` to the accumulated totals, update `updatedAt`, and save state.

If no triggers fired, report "No new qualifying activity this iteration" and stop.

Report a summary: creators polled, new post coins detected, growth triggers fired, buys executed, buys skipped (with reason — cap reached, low cap, quote failed), errors.

If `spentTotal >= totalCap`, tell the user the total spend cap is reached — they can stop scheduling further iterations or raise the cap in Manage Mode.

---

## Manage Mode

### Step 6: Add, remove, or edit creators and config

Read `.social-trader-state.json`, present the current creators and config, and ask the user what to change:

- **Add creator** — collect the handle, snapshot it as in Step 3 (`lastSeenPostAddress`, `lastSeenPostTimestamp`, `lastCreatorCoinMarketCap`), and append to `creators`.
- **Remove creator** — ask which handle(s) to drop.
- **Edit config** — update `budget`, `triggers`, `growthPercent`, `marketCapFloor`, `perIterationCap`, or `totalCap`.

Save the updated state and stop.

---

## Global Spending Budget

Beyond this skill's own `perIterationCap`/`totalCap`, the agent may have a **global, wallet-level spending budget** (set with `zora agent budget set`) that caps total spend across _all_ skills. Honor it on every buy:

**Before each buy**, check the global budget with the buy's ETH amount:

```bash
zora agent budget check --eth <amount> --json
```

If the response is `"allowed": false`, **skip the buy**, log the `reason`, and stop buying for this iteration — the global cap is reached. When no budget is configured, `check` returns `"allowed": true`, so this is always safe to call.

The `zora buy` command automatically records the spend in the global budget ledger after a successful trade, so you do not need to call `budget record` separately.

This is on top of — not a replacement for — the spend caps below.

## Safety Guards

- **Respect the spend caps** — never let a single iteration exceed `perIterationCap`, and never let `spentTotal` exceed `totalCap`.
- **Always quote before buying** — skip the buy if the quote fails.
- **Prefer addresses over names** for every buy and lookup to avoid coin-type ambiguity.
- **Don't act on stale or errored reads** — if `zora profile` or `zora get` returns an error, skip that creator and retry next iteration.
- **Advance markers regardless of buy outcome** — update `lastSeenPostAddress`/`lastSeenPostTimestamp` and `lastCreatorCoinMarketCap` even when a buy is skipped, so the same signal isn't re-triggered every iteration.
- **Cap new coins per creator per iteration** (max 2) to prevent runaway spending on a creator who posts a burst.
- **Never trade without explicit user confirmation** during Setup Mode.

## Resetting

Delete `.social-trader-state.json` to start fresh (new creators, triggers, or to clear spend tracking).
