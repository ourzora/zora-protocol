---
name: portfolio-digest
description: Produce a periodic portfolio and PnL digest for the agent's wallet and optionally deliver it. On first invocation, configures what to include and how to deliver it. Each subsequent invocation snapshots holdings, computes deltas vs the last snapshot, and reports. Read-only — never trades.
compatibility: Requires the Zora CLI (@zoralabs/cli).
---

# Portfolio Digest Skill

**Skill version 1.0.0**

## What This Skill Does

This skill produces a concise periodic portfolio and PnL digest for the agent's wallet — holdings and USD value, change versus the last snapshot, top movers, and how your own posts and creator coin are doing — and optionally delivers it to your operator. It is **read-only** — this skill never buys or sells anything. It runs **one iteration per invocation**: the first run configures what the digest includes and how it's delivered, and each subsequent run takes a fresh snapshot, computes deltas against the previous snapshot stored in state, formats the digest, and delivers it per your config. To run on a schedule, use the agent's native scheduler (e.g. Claude Code's `/loop`; see the Skills guide at https://agents.zora.com/guides/agent-skills).

## Requirements

Before starting, make sure you have the Zora CLI basics — if they're not already in your context, use the core Zora CLI skill, installed alongside this one as `zora-cli` (how to invoke the CLI, response shapes, error handling). Commands below use `zora` as shorthand for `npx @zoralabs/cli@latest`. Always use `--json` and check for `error` in responses.

## Step 1: Determine mode

Check if `.portfolio-digest-state.json` exists in the working directory.

- **File missing** → Setup Mode (Steps 2–3)
- **File exists** → ask the user what they want to do:
  - **Run** → Iteration Mode (Step 4)
  - **Edit** config → Manage Mode (Step 5)

---

## Setup Mode

### Step 2: Configure the digest

Ask the user how the digest should be composed and delivered.

**What to include** (each on by default; let the user turn any off):

- **Holdings & value** — every coin position with USD value, plus total portfolio USD
- **PnL vs last snapshot** — total value change and per-coin change since the previous run
- **Top movers** — the largest gainers and losers since the last snapshot (ask how many, default 3 each)
- **Your own performance** — how your creator coin and your posts are doing (requires your Zora handle)

If "your own performance" is on, ask for **your Zora handle** (the agent's own profile, e.g. `@myagent`).

**Delivery** — ask which of these to do (one or more):

- **Print** — print the digest to the operator (always available)
- **DM** — DM the digest to the operator via `zora dm send @<operator> "<digest>" --json`
- **None** — compute and store the snapshot but don't surface a digest

If **DM** is chosen, ask for the **operator handle** (`@handle` or `0x<address>`). The digest is only ever sent to this single operator handle.

### Step 3: Save state

Save `.portfolio-digest-state.json`. On first setup there is no prior snapshot yet, so `previousSnapshot` is `null` (the first iteration will populate it and report it as a baseline):

```json
{
  "config": {
    "includeHoldings": true,
    "includePnl": true,
    "includeTopMovers": true,
    "topMoversCount": 3,
    "includeOwnPerformance": true,
    "ownHandle": "@myagent",
    "delivery": ["print", "dm"],
    "operatorHandle": "@operator"
  },
  "previousSnapshot": null,
  "createdAt": "<ISO timestamp>",
  "updatedAt": "<ISO timestamp>"
}
```

Confirm the config back to the user and explain how to schedule the next iteration (see the Skills guide at https://agents.zora.com/guides/agent-skills). Stop.

---

## Iteration Mode

### Step 4: Snapshot, compute deltas, deliver

Read `.portfolio-digest-state.json` for the config and `previousSnapshot`.

**1. Take the current snapshot.**

```bash
zora balance --json
```

Read the top-level `walletAddress` (the wallet these balances belong to — smart wallet when configured, else EOA), the `wallet` array (tokens like ETH/USDC/ZORA, each with `usdValue`), and the `coins` array (positions, each with `name`, `symbol`, `address`, `balance`, `usdValue`, `priceUsd`, `marketCap`, `volume24h`).

If the user holds many positions, page the full holdings with:

```bash
zora balance coins --json
```

Check `pageInfo.hasNextPage` and pass `pageInfo.endCursor` as `--after` to continue until all positions are gathered.

Build the current snapshot:

- `totalUsd` = sum of every `wallet[].usdValue` plus every `coins[].usdValue`
- `perCoin` = a map of each coin `address` → its current `usdValue`

**2. If `config.includeOwnPerformance` is true**, read how your own coin and posts are doing (this is read-only — no trades):

```bash
zora profile <ownHandle> --json          # your profile overview (creator coin, totals)
zora profile posts <ownHandle> --json    # your post coins: marketCap, marketCapDelta24h, volume24h, createdAt
```

(`<ownHandle>` is `config.ownHandle` without the leading `@`.) Surface your creator coin's value and your posts' market caps and 24h deltas.

**3. Compute deltas vs `previousSnapshot`.**

- If `previousSnapshot` is `null` (first run): report this snapshot as the **baseline** — no deltas yet.
- Otherwise:
  - **Total change** = `currentTotalUsd - previousSnapshot.totalUsd` (also as a percentage)
  - **Per-coin movers**: for each coin address, compare current `usdValue` to `previousSnapshot.perCoin[address]`. A coin missing from the previous map is **new**; a coin in the previous map but absent now was **exited**.
  - **Top movers**: sort per-coin dollar changes and take the top `topMoversCount` gainers and losers.

**4. Format a concise digest** including only the sections the config enables:

```
Portfolio digest — <ISO timestamp>
Wallet: <walletAddress>
Total value: $<totalUsd>  (Δ $<change> / <pct>% since <previousSnapshot.timestamp>)

Holdings:
  <name> (<symbol>)  $<usdValue>  (Δ $<perCoinChange>)
  ...

Top movers:
  ▲ <name>  +$<change>
  ▼ <name>  -$<change>

Your coins/posts:
  <creator coin / post>  mcap $<marketCap>  (24h Δ <marketCapDelta24h>)
```

**5. Deliver per `config.delivery`:**

- `print` → print the digest to the operator.
- `dm` → send it to the operator only:
  ```bash
  zora dm send @<operatorHandle> "<digest>" --json
  ```
  Check the response for `error` before considering it delivered. If the DM fails (e.g. a brand-new conversation is rate-limited, per the retry suggestion in the error), still print the digest as a fallback and report the failure.
- `none` → don't surface the digest; just store the snapshot.

**6. Update state.** Replace `previousSnapshot` with the snapshot you just took, refresh `updatedAt`, and save:

```json
"previousSnapshot": {
  "timestamp": "<ISO timestamp>",
  "totalUsd": 1234.56,
  "perCoin": { "0x...": 12.34, "0x...": 56.78 }
}
```

Report a summary: total value, change since last snapshot, top movers, own-performance highlights, and how it was delivered.

---

## Manage Mode

### Step 5: Edit config

Read `.portfolio-digest-state.json`, present the current `config`, and ask the user what to change:

- Toggle any of `includeHoldings`, `includePnl`, `includeTopMovers`, `includeOwnPerformance`
- Change `topMoversCount` or `ownHandle`
- Change `delivery` (`print` / `dm` / `none`) or `operatorHandle`

Save the updated `config` and `updatedAt`. Leave `previousSnapshot` untouched so PnL continuity is preserved. Stop.

---

## Safety Guards

- **Read-only** — this skill never buys or sells. The only write it ever performs is an optional DM of the digest to the operator.
- **Operator-only delivery** — the digest is sent to the single `operatorHandle` in config and nowhere else. Never DM the digest to anyone else.
- **Read commands lag writes** by a few seconds — values reflect on-chain state from moments ago, which is fine for a periodic digest but means a digest taken right after a trade may not yet show it.
- **If `zora balance` returns an error**, do not overwrite `previousSnapshot` — report the failure and leave state intact so the next iteration compares against the last good snapshot.
- If a coin or profile fails to load, skip it and continue with the rest.

## Resetting

Delete `.portfolio-digest-state.json` to start fresh.
