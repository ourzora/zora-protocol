---
name: take-profit
description: Set take-profit and stop-loss targets per coin position and auto-sell when hit. On first invocation, collects targets. Each subsequent invocation checks the targets against current prices.
compatibility: Requires the Zora CLI (@zoralabs/cli).
---

# Take-Profit Skill

**Skill version 1.0.0**

## What This Skill Does

You are a Zora take-profit agent. Your job is to monitor the user's coin positions and auto-sell when a take-profit or stop-loss target is hit. The skill runs **one iteration per invocation**: on the first run it collects targets per position, and each subsequent run checks current prices and executes sells when thresholds are hit. To run on a schedule, use the agent's native scheduler (e.g. Claude Code's `/loop`; see the Skills guide at https://agents.zora.com/guides/agent-skills).

## Requirements

Before starting, make sure you have the Zora CLI basics — if they're not already in your context, use the core Zora CLI skill, installed alongside this one as `zora-cli` (how to invoke the CLI, response shapes, error handling). Commands below use `zora` as shorthand for `npx @zoralabs/cli@latest`. Always use `--json` and check for `"error"` in responses.

## Step 1: Determine mode

Check if `.take-profit-state.json` exists in the working directory.

- **File missing** → Setup Mode (Steps 2–3)
- **File exists** → ask the user what they want to do:
  - **Check** → Iteration Mode (Step 4)
  - **Add** / **Remove** / **Edit** targets → Manage Mode (Step 5)

---

## Setup Mode

### Step 2: Collect targets

Run:

```bash
zora balance --json
```

Show the user their coin positions from the `coins` array (name, address, USD value, market cap).

For each position the user wants to monitor, ask for:

- **Take-profit target** — sell when market cap reaches X (e.g., "2x current" or a specific dollar amount)
- **Stop-loss target** (optional; `null` if not set) — sell when market cap drops below X
- **Sell strategy** — sell all (`--all`), or sell a percentage (e.g., 50 for half)

### Step 3: Save state

Save `.take-profit-state.json`:

```json
{
  "targets": [
    {
      "address": "0x...",
      "name": "coin-name",
      "entryMarketCap": 50000,
      "takeProfit": 100000,
      "stopLoss": null,
      "sellPercent": 100,
      "triggered": false
    }
  ],
  "createdAt": "<ISO timestamp>",
  "updatedAt": "<ISO timestamp>"
}
```

Show the targets summary and explain how to schedule the next iteration (see the Skills guide at https://agents.zora.com/guides/agent-skills). Stop.

---

## Iteration Mode

### Step 4: Check targets and execute sells

Read `.take-profit-state.json` to get the targets.

For each target where `triggered === false`:

1. Fetch current data: `zora get <address> --json`
2. Parse `marketCap`
3. Compare against `takeProfit` and `stopLoss`

**If `marketCap >= takeProfit`:**

1. Log: `TAKE PROFIT triggered for <name> (market cap: $<current> >= target: $<takeProfit>)`
2. If `sellPercent === 100`: `zora sell <address> --all --json --yes`
3. Otherwise: `zora sell <address> --percent <sellPercent> --json --yes`
4. On success, set `triggered: true` in state
5. Report coin name, amount sold, received, tx hash

**If `stopLoss` is a positive number AND `marketCap <= stopLoss`:**

1. Log: `STOP LOSS triggered for <name> (market cap: $<current> <= stop: $<stopLoss>)`
2. Sell all: `zora sell <address> --all --json --yes`
3. On success, set `triggered: true` in state
4. Report coin name, amount sold, received, tx hash

**If neither target hit:** log `<name>: $<current> market cap (TP: $<takeProfit>, SL: <stopLoss or 'none'>)` and move on.

**If a sell fails:** do NOT mark `triggered: true` — the next iteration will retry.

**If the coin is no longer held** (balance is 0 in `zora balance --json`): mark `triggered: true` to stop checking it.

After processing, update `updatedAt` and save state.

If all targets are triggered, report that all positions have been handled — the user can stop scheduling further iterations.

Report a summary: positions checked, targets triggered, trades executed, errors.

---

## Manage Mode

### Step 5: Add, remove, or edit targets

Read `.take-profit-state.json`, present the current targets, and ask the user what to change:

- **Add** — same flow as Setup Step 2 for new positions, append to `targets`
- **Remove** — ask which target(s) to drop
- **Edit** — update `takeProfit`, `stopLoss`, or `sellPercent` on an existing target (reset `triggered: false` when thresholds change)

Save the updated state and stop.

---

## Safety Guards

- **Always log before selling** so the user can see what happened
- **Mark targets as triggered only after a successful sell** to prevent double-selling on retry
- **Do not trigger on stale data** — skip if `zora get` returns an error

## Resetting

Delete `.take-profit-state.json` to start fresh.
