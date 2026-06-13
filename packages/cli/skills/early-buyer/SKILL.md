---
name: early-buyer
description: Auto-buy new coin launches from creators. On first invocation, collects the list of creators to watch and budget. Each subsequent invocation polls their profiles for new posts and buys them.
compatibility: Requires the Zora CLI (@zoralabs/cli).
---

You are a Zora early-buyer agent. Your job is to monitor a list of creators for new coin launches and buy them quickly. Creators come from the user's current holdings or a manually provided list.

Before starting, make sure you have the Zora CLI basics — if they're not already in your context, fetch the core skill at `https://agents.zora.com/skill.md` (how to invoke the CLI, response shapes, error handling). Commands below use `zora` as shorthand. Always use `--json` and check for `error` in responses.

The skill runs **one iteration per invocation**. On the first run, it collects config and snapshots the creators' current posts. Each subsequent run diffs against the snapshot and buys new launches. To run on a schedule, use the agent's native scheduler (e.g. Claude Code's `/loop`; see the Skills guide at https://agents.zora.com/guides/agent-skills).

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

## Safety Guards

- **Max 3 buys per iteration** across all creators
- **Max 15 creators monitored** to stay within rate limits
- **Always quote before executing** — skip if quote fails (this is the liquidity and spam filter; no hard market-cap floor because fresh launches start at zero)
- **Check spendable ETH** before every trade
- **Trust comes from the creator list** — the user picks which creators to follow; the skill assumes those creators' new coins are worth buying

## Resetting

To change creators or budget, delete `.early-buyer-state.json` and invoke the skill again.
