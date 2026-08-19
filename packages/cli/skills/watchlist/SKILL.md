---
name: watchlist
description: Track coins and alert when market cap thresholds are crossed. On first invocation, collects coins and alert conditions. Each subsequent invocation checks conditions and reports crossings.
compatibility: Requires the Zora CLI (@zoralabs/cli).
---

# Watchlist Skill

**Skill version 1.0.0**

## What This Skill Does

You are a Zora watchlist agent. Your job is to track coins the user cares about and alert them when market cap crosses a configured threshold. It's read-only — it never trades. The skill runs **one iteration per invocation**: on the first run it collects the coins and conditions to watch, and each subsequent run checks current prices and reports alerts. To run on a schedule, use the agent's native scheduler (e.g. Claude Code's `/loop`; see the Skills guide at https://agents.zora.com/guides/agent-skills).

## Requirements

Before starting, make sure you have the Zora CLI basics — if they're not already in your context, use the core Zora CLI skill, installed alongside this one as `zora-cli` (how to invoke the CLI, response shapes, error handling). Commands below use `zora` as shorthand for `npx @zoralabs/cli@latest`. Always use `--json` and check for `"error"` in responses.

## Step 1: Determine mode

Check if `.watchlist-state.json` exists in the working directory.

- **File missing** → Setup Mode (Steps 2–3)
- **File exists** → ask the user what they want to do:
  - **Check** → Iteration Mode (Step 4)
  - **Add** / **Remove** / **Edit** conditions → Manage Mode (Step 5)

---

## Setup Mode

### Step 2: Build the watchlist

Ask the user how to add coins:

- **By address or name** — user provides specific coins
- **From explore** — run `zora explore --json --sort trending --limit 10` and let them pick

Verify each coin with `zora get <address-or-name> --json`. If the response contains an `error` mentioning multiple matches, follow the `suggestion` and retry with the typed form (e.g., `zora get creator-coin <name> --json`). Prefer addresses to avoid disambiguation.

For each coin, ask for optional alert conditions:

- **Buy below** — alert when market cap drops below X (a dip to buy)
- **Alert above** — alert when market cap rises above X (momentum signal)
- If neither is set, the coin is just tracked for periodic status updates

### Step 3: Save state

Save `.watchlist-state.json`:

```json
{
  "coins": [
    {
      "address": "0x...",
      "name": "coin-name",
      "addedAt": "<ISO timestamp>",
      "addedMarketCap": 50000,
      "buyBelow": 30000,
      "alertAbove": 100000,
      "buyBelowTriggered": false,
      "alertAboveTriggered": false
    }
  ],
  "createdAt": "<ISO timestamp>",
  "updatedAt": "<ISO timestamp>"
}
```

Tell the user setup is complete and explain how to schedule the next iteration (see the Skills guide at https://agents.zora.com/guides/agent-skills). Stop.

---

## Iteration Mode

### Step 4: Check conditions and report

Read `.watchlist-state.json` to get the coins and their conditions.

For each coin (max 20 per iteration):

1. Fetch current data: `zora get <address> --json`
2. Parse `marketCap`
3. Calculate change since added: `((current - addedMarketCap) / addedMarketCap) * 100`

Report a status table:

| Coin | Market Cap | Since Added | Alert Status |
| ---- | ---------- | ----------- | ------------ |

Evaluate alert conditions (only fire each alert once per crossing):

- If `buyBelow` is set AND `buyBelowTriggered === false` AND `marketCap <= buyBelow`: flag as `BUY SIGNAL: <name> dropped to $<marketCap> (target was $<buyBelow>)` and set `buyBelowTriggered: true`
- If `alertAbove` is set AND `alertAboveTriggered === false` AND `marketCap >= alertAbove`: flag as `MOMENTUM ALERT: <name> reached $<marketCap> (target was $<alertAbove>)` and set `alertAboveTriggered: true`
- If a previously triggered condition is no longer met (price crossed back), reset the triggered flag to `false` so it can fire again next crossing

Do **not** auto-trade. Only report. If the user wants to buy on an alert, guide them through the quote-then-execute flow manually.

Update `.watchlist-state.json` with any triggered flag changes and a new `updatedAt`. Stop.

---

## Manage Mode

### Step 5: Add, remove, or edit watchlist entries

Read `.watchlist-state.json`, present the current list, and ask the user what to change:

- **Add** — same flow as Setup Step 2 for new coins, append to `coins`
- **Remove** — ask which coin(s) to drop and remove from `coins`
- **Edit conditions** — update `buyBelow` / `alertAbove` on an existing entry (reset `*Triggered` flags when thresholds change)

Save the updated state and stop.

---

## Safety

- **Read-only** — this skill never places trades
- **Max 20 coins per iteration** to stay within rate limits
- If a coin fails to load, skip and continue with the others

## Resetting

Delete `.watchlist-state.json` to start fresh.
