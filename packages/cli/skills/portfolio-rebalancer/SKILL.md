---
name: portfolio-rebalancer
description: Maintain target portfolio allocations and rebalance each iteration. On first invocation, collects target allocations (by category or per coin), a drift tolerance band, and a minimum trade size. Each subsequent invocation measures current allocation by USD value and trims overweight buckets / tops up underweight ones.
compatibility: Requires the Zora CLI (@zoralabs/cli).
---

# Portfolio Rebalancer Skill

**Skill version 1.0.0**

## What This Skill Does

You are a Zora portfolio-rebalancer agent. Your job is to keep the user's holdings aligned with a target allocation — measuring current weights by USD value each iteration, then trimming buckets that have drifted overweight and topping up buckets that have drifted underweight. The skill runs **one iteration per invocation**: on the first run it collects the target allocation and tolerances, and each subsequent run reads balances, computes drift, and executes the trades needed to pull the portfolio back toward target. To run on a schedule, use the agent's native scheduler (e.g. Claude Code's `/loop`; see the Skills guide at https://agents.zora.com/guides/agent-skills).

## Requirements

Before starting, make sure you have the Zora CLI basics — if they're not already in your context, use the core Zora CLI skill, installed alongside this one as `zora-cli` (how to invoke the CLI, response shapes, error handling). Commands below use `zora` as shorthand for `npx @zoralabs/cli@latest`. Always use `--json` and check for `error` in responses.

## Step 1: Determine mode

Check if `.portfolio-rebalancer-state.json` exists in the working directory.

- **File missing** → Setup Mode (Steps 2–3)
- **File exists** → ask the user what they want to do:
  - **Rebalance** → Iteration Mode (Step 4)
  - **Edit** targets, drift band, or min trade size → Manage Mode (Step 5)

---

## Setup Mode

### Step 2: Collect the target allocation

Run:

```bash
zora balance --json
```

Show the user their current portfolio from the response: the `wallet` array (ETH/USDC/ZORA with `usdValue`) and the `coins` array (each entry has `name`, `address`, `type`, `usdValue`). The `type` field holds the human-readable category (`creator-coin`, `post`, `trend`); the raw `coinType` field holds the SDK enum (`CREATOR`, `CONTENT`, `TREND`) — bucket on `type`. Sum all `usdValue` fields to show total portfolio value.

Ask the user which **allocation mode** they want:

- **By category** — target percentages across buckets, summing to 100. The standard buckets are:
  - `creator-coin` — coins where `type === "creator-coin"`
  - `post` — coins where `type === "post"`
  - `trend` — coins where `type === "trend"`
  - `cash` — the `wallet` array (ETH + USDC + ZORA)
- **By coin** — target percentage per specific coin address, summing to 100 (any remainder is treated as `cash`).

Validate that the targets sum to 100. Then collect two tolerances:

- **Drift band** (percent) — only rebalance a bucket when its actual weight is more than this many percentage points off target (suggest 5). Prevents churning on small moves.
- **Minimum trade size** (USD) — skip any computed trade smaller than this, to avoid dust trades (suggest $5).

### Step 3: Save state

Save `.portfolio-rebalancer-state.json`:

```json
{
  "mode": "category",
  "targets": {
    "creator-coin": 40,
    "post": 25,
    "trend": 15,
    "cash": 20
  },
  "driftBand": 5,
  "minTrade": 5,
  "lastRebalance": null,
  "createdAt": "<ISO timestamp>",
  "updatedAt": "<ISO timestamp>"
}
```

For **by coin** mode, `targets` keys are coin addresses (e.g. `"0xabc...": 30`) plus an optional `"cash"` key for the remainder.

Show the target summary and explain how to schedule the next iteration (see the Skills guide at https://agents.zora.com/guides/agent-skills). Stop.

---

## Iteration Mode

### Step 4: Measure drift and rebalance

Read `.portfolio-rebalancer-state.json` to get `mode`, `targets`, `driftBand`, and `minTrade`.

**Measure the current allocation:**

```bash
zora balance --json
```

From the response:

1. Read the top-level `walletAddress` (the wallet these balances belong to) and note it in your report.
2. Sum every `usdValue` in the `wallet` array → `cashUsd`. Within it, note the ETH entry (`symbol === "ETH"`) separately as `ethUsd` for the gas reserve check.
3. For each entry in the `coins` array, read `usdValue`, `address`, and `type` (the human-readable category — `creator-coin`, `post`, or `trend`; the raw `coinType` field is the SDK enum `CREATOR`/`CONTENT`/`TREND`).
4. Compute the portfolio total = `cashUsd` + sum of all coin `usdValue`.

**Bucket the coins:**

- **Category mode** — group coin `usdValue` by `type` into `creator-coin`, `post`, and `trend`; `cash` is `cashUsd`.
- **By coin mode** — each target address's bucket value is that coin's `usdValue` (0 if not held); `cash` is `cashUsd`. Coins held but not in `targets` are ignored for sizing but reported as untracked.

**Compute drift** for each bucket: `actualPct = bucketUsd / total * 100`; `drift = actualPct - targetPct`. The dollar delta to move is `delta = (targetPct - actualPct) / 100 * total`.

**For each bucket where `abs(drift) > driftBand`:**

- **Overweight** (`drift > driftBand`, positive `bucketUsd`) → trim by `abs(delta)` USD:
  - **By coin mode:** `zora sell <address> --usd <delta> --yes --json` (or `--percent <p>` if selling a clean fraction of the position). Prefer the coin's `address`.
  - **Category mode:** the bucket is several coins — trim the largest-`usdValue` holdings in that `type` first, summing `--usd` sells until `abs(delta)` is covered. Skip any individual sell below `minTrade`.
  - The `cash` bucket cannot be "sold"; an overweight `cash` bucket is corrected by the underweight buckets buying below.
- **Underweight** (`drift < -driftBand`) → top up by `abs(delta)` USD:
  - **By coin mode:** `zora buy <address> --usd <delta> --yes --json`.
  - **Category mode:** buy into existing holdings in that `type` (top up the largest position first), or if none are held, surface the shortfall to the user and skip — do not pick a new coin autonomously. Skip any buy below `minTrade`.
  - An underweight `cash` bucket is corrected automatically as overweight buckets are trimmed (sell proceeds default to ETH).

**Before any single trade above $50 (or above the user's configured threshold), quote first:**

```bash
zora sell <address> --usd <delta> --quote --json
zora buy <address> --usd <delta> --quote --json
```

Confirm the quote looks reasonable, then re-run without `--quote` and with `--yes` to execute.

**Skip any trade smaller than `minTrade`.** Log it as skipped rather than executing dust.

**Gas reserve:** never let the `cash`/ETH bucket be fully spent. If a top-up would drive ETH `usdValue` toward zero, cap the buy so a buffer remains — the CLI keeps a gas reserve on `--all`/`--percent` sells automatically, but enforce a floor here too.

After processing, record a `lastRebalance` summary on the state and update `updatedAt`:

```json
"lastRebalance": {
  "at": "<ISO timestamp>",
  "totalUsd": 1234.56,
  "trades": [
    { "action": "sell", "address": "0x...", "usd": 42.0, "txHash": "0x..." }
  ],
  "skipped": [{ "bucket": "trend", "reason": "below minTrade" }]
}
```

**Read commands lag writes by a few seconds.** Do not re-query `balance` immediately after a trade to verify — trust the trade response (tx hash = on-chain) and let the next scheduled iteration pick up refreshed balances.

Report a summary: wallet address, total USD value, each bucket's target vs actual percent, trades executed (with tx hashes), trades skipped (with reason), and any errors. If every bucket is within the drift band, report "No rebalancing needed — all buckets within ±<driftBand>%" and stop.

---

## Manage Mode

### Step 5: Edit targets, drift band, or min trade size

Read `.portfolio-rebalancer-state.json`, present the current `targets`, `driftBand`, and `minTrade`, and ask the user what to change:

- **Targets** — update one or more bucket/coin percentages. Re-validate that they sum to 100.
- **Drift band** — update the tolerance.
- **Min trade size** — update the dust floor.

Save the updated state and stop. Changing targets takes effect on the next iteration.

---

## Safety Guards

- **Quote before large trades** — `--quote` first on any trade above your threshold (e.g. $50); confirm before executing.
- **Respect `minTrade`** — never execute a computed trade below the dust floor; log it skipped instead.
- **Keep a gas reserve** — never allocate the ETH/cash bucket down to zero; always leave a buffer for gas.
- **Honor the drift band** — only trade buckets outside `±driftBand`; do not churn on small moves.
- **Prefer addresses over names** to avoid coin-type ambiguity.
- **Do not trade on stale data** — if `zora balance` returns an error, skip the iteration rather than rebalancing blind.
- **Never buy a new coin autonomously** in category mode — only top up coins already held; surface unfillable shortfalls to the user.

## Resetting

Delete `.portfolio-rebalancer-state.json` to start fresh with a new allocation.
