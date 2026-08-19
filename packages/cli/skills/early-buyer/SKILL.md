---
name: early-buyer
description: Auto-buy new coin launches from creators. On first invocation, collects the list of creators to watch and budget. Each subsequent invocation polls their profiles for new posts and buys them.
compatibility: Requires the Zora CLI (@zoralabs/cli).
---

# Early Buyer Skill

**Skill version 1.0.0**

## What This Skill Does

You are a Zora early-buyer agent. Your job is to monitor a list of creators for new coin launches and buy them quickly — creators come from the user's current holdings or a manually provided list. The skill runs **one iteration per invocation**: on the first run it collects config and snapshots the creators' current posts, and each subsequent run diffs against the snapshot and buys new launches. To run on a schedule, use the agent's native scheduler (e.g. Claude Code's `/loop`; see the Skills guide at https://agents.zora.com/guides/agent-skills).

## Requirements

Before starting, make sure you have the Zora CLI basics — if they're not already in your context, use the core Zora CLI skill, installed alongside this one as `zora-cli` (how to invoke the CLI, response shapes, error handling). Commands below use `zora` as shorthand for `npx @zoralabs/cli@latest`. Always use `--json` and check for `"error"` in responses.

## Step 1: Determine mode

Check if `.early-buyer-state.json` exists in the working directory.

- **File missing** → Setup Mode (Steps 2–3)
- **File exists** → Iteration Mode (Step 4)

---

## Setup Mode

### Step 2: Collect configuration

Ask the user:

1. **Creator source**:
   - **Auto-detect** — extract unique `creatorHandle` values from the `coins` array of `zora balance --json`
   - **Manual list** — user provides specific handles
2. **Budget per new coin** in ETH (suggest 0.001 ETH default)

### Step 3: Snapshot and save state

For each creator (max 15), run:

```bash
zora profile posts <handle> --json --limit 20
```

Collect all `address` values from each response's `posts` array.

Save `.early-buyer-state.json`:

```json
{
  "creators": {
    "<handle1>": ["0xaddr1", "0xaddr2"],
    "<handle2>": ["0xaddr3"]
  },
  "budget": "<eth-amount>",
  "createdAt": "<ISO timestamp>",
  "updatedAt": "<ISO timestamp>"
}
```

Tell the user setup is complete: number of creators tracked, total coins in snapshot, budget per trade. Explain how to schedule the next iteration (see the Skills guide at https://agents.zora.com/guides/agent-skills). Stop.

---

## Iteration Mode

### Step 4: Check for new launches and buy

Read `.early-buyer-state.json` to get the creator list and budget.

For each creator in the snapshot, run:

```bash
zora profile posts <handle> --json --limit 20
```

Compare returned `address` values against the creator's snapshot list. Any address in the response that is NOT in the snapshot is a new coin launch.

For each new coin (max 3 per iteration across all creators):

1. Fetch details: `zora get <coinAddress> --json` (for reporting context only — don't gate on market cap, new launches start near zero)
2. Check spendable ETH: `zora balance --json` (wallet array, `symbol === "ETH"`)
3. Skip if insufficient ETH
4. Quote: `zora buy <coinAddress> --eth <budget> --quote --json` — if the quote errors (no liquidity, banned coin, etc.), skip and continue
5. If quote succeeds, execute: `zora buy <coinAddress> --eth <budget> --json --yes`
6. Report creator handle, coin name, amount received, tx hash

After processing, update `.early-buyer-state.json`:

- Replace each creator's address list with the current posts array from this iteration
- Update `updatedAt`

Report a summary: creators checked, new coins found, trades executed, skipped (with reason), errors.

If a creator's profile fails to load, skip and continue with the others.

---

## Global Spending Budget

This skill caps each buy to a fixed `budget` and otherwise relies on wallet balance — the agent's **global, wallet-level spending budget** (set with `zora agent budget set`) adds the missing cumulative ceiling across _all_ skills. Honor it on every buy:

**Before each buy**, check the global budget with the buy's ETH amount:

```bash
zora agent budget check --eth <amount> --json
```

If the response is `"allowed": false`, **skip the buy**, log the `reason`, and stop buying for this iteration — the global cap is reached. When no budget is configured, `check` returns `"allowed": true`, so this is always safe to call.

The `zora buy` command automatically records the spend in the global budget ledger after a successful trade, so you do not need to call `budget record` separately.

## Safety Guards

- **Max 3 buys per iteration** across all creators
- **Max 15 creators monitored** to stay within rate limits
- **Always quote before executing** — skip if quote fails (this is the liquidity and spam filter; no hard market-cap floor because fresh launches start at zero)
- **Check spendable ETH** before every trade
- **Trust comes from the creator list** — the user picks which creators to follow; the skill assumes those creators' new coins are worth buying

## Resetting

To change creators or budget, delete `.early-buyer-state.json` and invoke the skill again.
