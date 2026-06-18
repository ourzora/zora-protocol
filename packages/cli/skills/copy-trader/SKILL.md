---
name: copy-trader
description: Mirror another user's trades. On first invocation, asks whether to copy existing holdings (all, top by value, top by market cap, most active, or most recent) and/or future trades. Each subsequent invocation runs one poll cycle using the target's recent trade activity.
compatibility: Requires the Zora CLI (@zoralabs/cli).
---

# Copy Trader Skill

**Skill version 1.0.0**

## What This Skill Does

You are a Zora copy-trading agent. Your job is to replicate another user's trades — either by copying their current holdings once, by mirroring new trades they make going forward, or both. The skill runs **one iteration per invocation**: on the first run it collects config and does optional initial work, and on subsequent runs it polls for new trades from the target and mirrors them. To run on a schedule, use the agent's native scheduler (e.g. Claude Code's `/loop`; see the Skills guide at https://agents.zora.com/guides/agent-skills).

## Requirements

Before starting, make sure you have the Zora CLI basics — if they're not already in your context, use the core Zora CLI skill, installed alongside this one as `zora-cli` (how to invoke the CLI, response shapes, error handling). Commands below use `zora` as shorthand for `npx @zoralabs/cli@latest`. Always use `--json` and check for `error` in responses.

## Step 1: Determine mode

Check if `.copy-trader-state.json` exists in the working directory.

- **File missing** → Setup Mode (Steps 2–4)
- **File exists** → Iteration Mode (Step 5)

---

## Setup Mode

### Step 2: Collect configuration

Ask the user:

1. **Target handle** — the Zora username or wallet address to copy
2. **Copy strategy** — what to copy:
   - **Existing positions** — buy into the target's current holdings now (one-shot)
   - **Future trades** — mirror new trades from now on (runs each iteration)
   - **Both** — copy existing positions first, then mirror future trades
3. **Budget per trade** — ETH amount per position (suggest 0.001 ETH default)

If the user chose **existing positions** or **both**, also ask:

4. **Which holdings to copy**:
   - **All holdings** — every position the target holds
   - **Top N by value** — N highest-value positions (suggest top 5)
   - **Top N by market cap** — N positions in the largest coins (suggest top 5)
   - **Most active N** — N positions with the strongest recent price movement (suggest top 5)
   - **Most recent N** — N positions the target most recently bought (suggest top 5)

If the user chose **future trades** or **both**, also ask:

5. **Mirror sells** — whether to sell when the target sells (default: no)

### Step 3: Validate and snapshot

Run these commands to verify the setup works:

```bash
zora wallet info --json
zora balance --json
zora profile holdings <target> --json --limit 1
```

Fail fast on any error. Show the user: their wallet address, ETH balance (from `wallet` array, `symbol === "ETH"`), and whether the target has any holdings.

If **future trades** is in scope, snapshot the target's latest trade timestamp now so Iteration Mode knows where to start polling from:

```bash
zora profile trades <target> --json --limit 1
```

Record the `timestamp` of the newest trade (or `null` if none). This becomes `lastProcessedTimestamp` in state.

### Step 4: Copy existing positions (if selected) and save state

Skip this step if the user only chose **future trades**.

Fetch holdings using the strategy that matches the user's filter choice:

- **All holdings**: `zora profile holdings <target> --json --limit 20`
- **Top N by value**: `zora profile holdings <target> --sort usd-value --limit <N> --json`
- **Top N by market cap**: `zora profile holdings <target> --sort market-cap --limit <N> --json`
- **Most active N**: `zora profile holdings <target> --sort price-change --limit <N> --json`
- **Most recent N**: derive from trade activity:
  1. `zora profile trades <target> --json --limit 20` (most-recent-first)
  2. `zora profile holdings <target> --json --limit 20`
  3. Walk trades in order, keeping `side === "BUY"` entries where `coinAddress` is in current holdings
  4. Deduplicate by `coinAddress`, take the first N

Exclude coins the user already holds (cross-reference with the `coins` array from `zora balance --json`).

Preview the filtered list to the user as a table (coin name, market cap, target's USD value, action). Show total ETH needed. Ask for confirmation before trading.

On confirmation, for each coin (max 10 per batch):

1. Quote: `zora buy <coinAddress> --eth <budget> --quote --json`
2. If quote succeeds, execute: `zora buy <coinAddress> --eth <budget> --json --yes`
3. Report coin name, amount received, tx hash

After all buys complete, write `.copy-trader-state.json`:

```json
{
  "target": "<handle-or-address>",
  "budget": "<eth-amount>",
  "mirrorSells": false,
  "lastProcessedTimestamp": "<ISO timestamp or null>",
  "createdAt": "<ISO timestamp>",
  "updatedAt": "<ISO timestamp>"
}
```

If the user only chose **existing positions** (no future monitoring), write state with `lastProcessedTimestamp: null` and tell the user they're done — no need to re-invoke.

If **future trades** is in scope, tell the user setup is complete and explain how to schedule the next iteration (see the Skills guide at https://agents.zora.com/guides/agent-skills).

---

## Iteration Mode

### Step 5: Poll and mirror new trades

Read `.copy-trader-state.json` to get `target`, `budget`, `mirrorSells`, and `lastProcessedTimestamp`.

Fetch the target's recent trades:

```bash
zora profile trades <target> --json --limit 20
```

Filter to trades where `timestamp > lastProcessedTimestamp` (or all trades if `lastProcessedTimestamp` is null). The API returns most-recent-first; reverse the filtered list so trades are processed in chronological order (oldest new trade first).

If there are no new trades, report "No new activity since <lastProcessedTimestamp>" and stop.

For each new trade (max 3 per iteration):

- **BUY**:
  1. Check spendable ETH: `zora balance --json` (wallet array, `symbol === "ETH"`)
  2. Skip if market cap < $1,000: fetch with `zora get <coinAddress> --json`
  3. Quote: `zora buy <coinAddress> --eth <budget> --quote --json`
  4. If quote succeeds, execute: `zora buy <coinAddress> --eth <budget> --json --yes`
  5. Report target's side, coin name, our amount received, tx hash
- **SELL** (only if `mirrorSells` is true):
  1. Check if we hold this coin (from `zora balance --json` `coins` array)
  2. If held, sell all: `zora sell <coinAddress> --all --json --yes`
  3. Report coin name, amount sold, tx hash

After processing, update `lastProcessedTimestamp` to the `timestamp` of the newest trade processed this iteration, update `updatedAt`, and save state.

If `pageInfo.hasNextPage` was true AND more than 20 new trades accumulated since the last run (very active trader), note in the report that some trades were skipped — the user should either reduce the poll interval or manually sync.

Report a summary: trades processed, trades executed, trades skipped (reason), errors.

---

## Global Spending Budget

This skill caps each trade to a fixed `budget` but does not track cumulative spend — the agent's **global, wallet-level spending budget** (set with `zora agent budget set`) provides that shared ceiling across _all_ skills. Honor it on every mirrored buy:

**Before each buy**, check the global budget with the buy's ETH amount:

```bash
zora agent budget check --eth <amount> --json
```

If the response is `"allowed": false`, **skip the buy**, log the `reason`, and stop mirroring buys for this iteration — the global cap is reached. When no budget is configured, `check` returns `"allowed": true`, so this is always safe to call.

The `zora buy` command automatically records the spend in the global budget ledger after a successful trade, so you do not need to call `budget record` separately.

## Safety Guards

- **Max 3 trades per iteration** to prevent runaway spending
- **Max 10 buys in the Setup copy-existing step**
- **Always quote before executing** — skip the trade if quote fails
- **Check spendable balance** before every trade — stop trading if ETH runs low
- **Skip low-cap coins** — ignore trades with market cap below $1,000
- **Never trade without explicit user confirmation** during Setup Mode

## Resetting

To re-run setup (for a different target or strategy), delete `.copy-trader-state.json` and invoke the skill again.
