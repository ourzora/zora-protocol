---
name: trend-sniper
description: Watch the global trending feed for new trend coins and snipe them during viral moments. On first invocation, collects a per-snipe budget, trigger rules (first appearance and/or 24h volume threshold), a spend cap, and an optional max market cap. Each subsequent invocation polls the trending feed and buys new qualifying trend coins.
compatibility: Requires the Zora CLI (@zoralabs/cli).
---

# Trend Sniper Skill

**Skill version 1.0.0**

## What This Skill Does

You are a Zora trend-sniper agent. Your job is to watch the market-wide trending feed for newly surfacing trend coins and snipe them — buying into viral moments as they break, within a budget and spend cap the user sets. This is distinct from following specific creators: you react to whatever the whole market is pushing up the trending list.

The skill runs **one iteration per invocation**. On the first run, it collects config and snapshots the current trending feed. On subsequent runs, it polls the trending feed, compares against what it has already seen, and buys new qualifying coins. To run on a schedule, use the agent's native scheduler (e.g. Claude Code's `/loop`; see the Skills guide at https://agents.zora.com/guides/agent-skills).

## Requirements

Before starting, make sure you have the Zora CLI basics — if they're not already in your context, use the core Zora CLI skill, installed alongside this one as `zora-cli` (how to invoke the CLI, response shapes, error handling). Commands below use `zora` as shorthand for `npx @zoralabs/cli@latest`. Always use `--json` and check for `error` in responses.

## Step 1: Determine mode

Check if `.trend-sniper-state.json` exists in the working directory.

- **File missing** → Setup Mode (Steps 2–4)
- **File exists** → ask the user what they want to do:
  - **Snipe** → Iteration Mode (Step 5)
  - **Edit** config (budget, triggers, caps) → Manage Mode (Step 6)

---

## Setup Mode

### Step 2: Collect configuration

Ask the user:

1. **Budget per snipe** — how much to spend on each coin. ETH (suggest 0.005 ETH default) or USD.
2. **Trigger mode** — when to snipe a coin:
   - **On appearance** — buy when a trend coin first shows up on the trending list
   - **On volume** — buy when a trend coin crosses a 24h volume threshold
   - **Either** — snipe if either condition is met (default)
3. **Volume threshold** — the 24h USD volume a coin must cross for the **volume** trigger (suggest $10,000 default). Skip if trigger mode is **on appearance** only.
4. **Spend cap** — the most to spend in a single day (`dailyCap`) and/or in total over the strategy's life (`totalCap`). Either may be `null`. Suggest a `dailyCap` so a viral burst can't drain the wallet.
5. **Max market cap** (optional; `null` if not set) — skip coins already larger than this so you don't snipe ones that have peaked.

### Step 3: Validate and snapshot the feed

Run these to verify the setup works and capture a baseline:

```bash
zora wallet info --json
zora balance --json
zora explore --sort trending --type all --json
```

Fail fast on any error. Show the user their wallet address and spendable ETH (from the `wallet` array, `symbol === "ETH"`).

From the `explore` results, collect the addresses of every coin whose `coinType` is `trend`. These are coins already trending **before** you started — seed them into `seen` so the first iteration doesn't snipe the entire existing list as if it were brand new.

### Step 4: Save state

Write `.trend-sniper-state.json`:

```json
{
  "config": {
    "budget": { "kind": "eth", "amount": "0.005" },
    "triggerMode": "either",
    "volumeThreshold": 10000,
    "dailyCap": 0.05,
    "totalCap": null,
    "maxMarketCap": null
  },
  "seen": ["0x..."],
  "buys": [],
  "spentToday": 0,
  "spentTotal": 0,
  "capDate": "<YYYY-MM-DD>",
  "createdAt": "<ISO timestamp>",
  "updatedAt": "<ISO timestamp>"
}
```

`budget.kind` is `"eth"` or `"usd"`; `triggerMode` is `"appearance"`, `"volume"`, or `"either"`. `spentToday`/`spentTotal` are tracked in the **same unit** as `budget.kind`. `capDate` is the day `spentToday` applies to.

Show the config summary and explain how to schedule the next iteration (see the Skills guide at https://agents.zora.com/guides/agent-skills). Stop.

---

## Iteration Mode

### Step 5: Poll the trending feed and snipe new coins

Read `.trend-sniper-state.json` for `config`, `seen`, `buys`, `spentToday`, `spentTotal`, and `capDate`.

**Reset the daily counter first.** If `capDate` is not today's date (UTC), set `spentToday` to `0` and `capDate` to today.

Fetch the trending trend coins:

```bash
zora explore --sort trending --type all --json
```

Keep only results where `coinType === "trend"`. Split into:

- **Already seen** — `address` is in `seen`
- **New** — `address` is not in `seen`

For each coin still in the feed, evaluate its trigger. A coin **qualifies** when:

- Trigger mode **appearance** or **either**: it is **new** this iteration (not in `seen`), OR
- Trigger mode **volume** or **either**: its 24h volume `>= config.volumeThreshold`

To get reliable volume and market cap before buying, pull details:

```bash
zora get <address> --json
```

`get <address>` returns `marketCap`, `volume24h`, and `uniqueHolders` (all as strings). Use its `marketCap` and `volume24h` (prefer them over the summary in `explore`). Skip the coin if:

- `config.maxMarketCap` is set AND `marketCap > config.maxMarketCap` (already too large), or
- `zora get` returns an error (don't act on stale or missing data).

Add every new address to `seen` as soon as you observe it — whether or not you buy — so it isn't re-evaluated as "new" next iteration.

**Respect the spend cap before each buy.** Compute the buy size in `budget.kind` units. Skip (and stop buying further this iteration) if it would push `spentToday` over `dailyCap` or `spentTotal` over `totalCap` (when those are non-null).

For each qualifying coin (max 3 buys per iteration):

1. Log: `SNIPE <name> (<address>) — trigger: <appearance|volume>, mcap: $<marketCap>, vol24h: $<volume24h>`
2. Quote first: `zora buy <address> --eth <amount> --quote --json` (or `--usd <amount>`)
3. If the quote succeeds and looks reasonable, execute:
   - ETH budget: `zora buy <address> --eth <amount> --yes --json`
   - USD budget: `zora buy <address> --usd <amount> --yes --json`
4. On success, append to `buys`: `{ address, name, trigger, amount, kind, marketCap, volume24h, txHash, timestamp }`, and add `amount` to both `spentToday` and `spentTotal`.
5. Report coin name, amount received, tx hash.

**If a buy fails:** do NOT record it in `buys` and do NOT add to the spend counters — the coin stays in `seen`, so it won't retry on appearance, but the volume trigger can still pick it up later if it keeps climbing.

If no coins qualify, report "No new trending snipes this iteration" and stop.

After processing, update `updatedAt` and save state.

Report a summary: trending trend coins seen, new this iteration, snipes executed, snipes skipped (reason: too large / cap reached / quote failed), `spentToday` / `spentTotal` vs caps, errors.

---

## Manage Mode

### Step 6: Edit configuration

Read `.trend-sniper-state.json`, present the current `config`, `spentToday`/`spentTotal`, and the count of `seen` and `buys`, then ask what to change:

- **Budget** — update `budget.kind` and `budget.amount`
- **Triggers** — update `triggerMode` and/or `volumeThreshold`
- **Caps** — update `dailyCap` and/or `totalCap`
- **Max market cap** — update or clear `maxMarketCap`

Leave `seen`, `buys`, and the spend counters intact. Save the updated state and stop.

---

## Global Spending Budget

Beyond this skill's own `dailyCap`/`totalCap`, the agent may have a **global, wallet-level spending budget** (set with `zora agent budget set`) that caps total spend across _all_ skills. Honor it on every snipe:

**Before each buy**, check the global budget with the buy's ETH amount:

```bash
zora agent budget check --eth <amount> --json
```

If the response is `"allowed": false`, **skip the buy**, log the `reason`, and stop sniping for this iteration — the global cap is reached. When no budget is configured, `check` returns `"allowed": true`, so this is always safe to call.

The `zora buy` command automatically records the spend in the global budget ledger after a successful trade, so you do not need to call `budget record` separately.

This is on top of — not a replacement for — the spend caps below.

## Safety Guards

- **Always quote before executing** — skip the snipe if the quote fails or looks off.
- **Never exceed the spend cap** — stop buying for the iteration once `dailyCap` or `totalCap` would be crossed.
- **Max 3 snipes per iteration** to prevent a viral burst from draining the wallet in one cycle.
- **Skip coins that are already too large** when `maxMarketCap` is set — the goal is early entry, not chasing the top.
- **Always log before buying** so the user can see exactly what was sniped and why.
- **Don't act on stale data** — skip any coin whose `zora get` returns an error.
- **Check spendable ETH** (from `zora balance --json`, `wallet` array, `symbol === "ETH"`) and stop sniping if it runs low.
- **Prefer addresses over names** — always buy and look up by the `0x` address from the feed, never by ticker.

## Resetting

Delete `.trend-sniper-state.json` to start fresh (clears `seen`, `buys`, and spend counters). The next iteration re-snapshots the trending feed as the new baseline.
