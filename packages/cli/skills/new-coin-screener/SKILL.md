---
name: new-coin-screener
description: Poll the global new-coin feed and auto-buy coins that pass a screen (minimum market cap, minimum holder count, optional creator allowlist, coin type). On first invocation, collects the screen criteria and spend caps. Each subsequent invocation scans the new feed, evaluates each unseen coin, and buys the ones that pass.
compatibility: Requires the Zora CLI (@zoralabs/cli).
---

# New Coin Screener Skill

**Skill version 1.0.0**

## What This Skill Does

You are a Zora new-coin-screener agent. Your job is to watch the market-wide new-coin feed and auto-buy freshly launched coins that pass a screen you configure with the user. Unlike the early-buyer skill (which watches a specific list of creators), you watch the entire global `new` feed and gate purchases on objective criteria. The skill runs **one iteration per invocation**: the first run collects the screen criteria and spend caps, and each subsequent run scans the new feed, evaluates each coin it hasn't seen yet, and buys the ones that pass. To run on a schedule, use the agent's native scheduler (e.g. Claude Code's `/loop`; see the Skills guide at https://agents.zora.com/guides/agent-skills).

## Requirements

Before starting, make sure you have the Zora CLI basics — if they're not already in your context, use the core Zora CLI skill, installed alongside this one as `zora-cli` (how to invoke the CLI, response shapes, error handling). Commands below use `zora` as shorthand for `npx @zoralabs/cli@latest`. Always use `--json` and check for `error` in responses.

## Step 1: Determine mode

Check if `.new-coin-screener-state.json` exists in the working directory.

- **File missing** → Setup Mode (Steps 2–3)
- **File exists** → ask the user what they want to do:
  - **Scan** → Iteration Mode (Step 4)
  - **Edit** criteria or caps → Manage Mode (Step 5)

---

## Setup Mode

### Step 2: Collect screen criteria

Ask the user for:

1. **Minimum market cap** in USD — skip coins below this (e.g., 5000). Fresh launches start near zero, so this filters out coins that haven't gained any traction yet.
2. **Minimum holder count** — skip coins with fewer holders than this (e.g., 10).
3. **Creator-handle allowlist** (optional) — if provided, only buy coins whose creator handle is in this list; otherwise consider any creator. `null` for no allowlist.
4. **Coin type filter** — which feed to scan. Valid `--type` values are `all`, `creator-coin`, `post`, and `trend` (default `all`).
5. **Budget per buy** in ETH (suggest 0.001 ETH default).
6. **Daily spend cap** and **total spend cap** in ETH — never spend more than these across an iteration cycle. The daily cap resets each calendar day.

### Step 3: Save state

Save `.new-coin-screener-state.json`:

```json
{
  "criteria": {
    "minMarketCap": 5000,
    "minHolders": 10,
    "creatorAllowlist": null,
    "type": "all",
    "budget": "0.001",
    "dailyCapEth": "0.05",
    "totalCapEth": "0.5"
  },
  "seen": ["0xaddr1", "0xaddr2"],
  "buys": [
    {
      "address": "0x...",
      "name": "coin-name",
      "creatorHandle": "<handle>",
      "marketCap": 7200,
      "holders": 14,
      "eth": "0.001",
      "txHash": "0x...",
      "boughtAt": "<ISO timestamp>"
    }
  ],
  "spentToday": "0",
  "spentTotal": "0",
  "spendDate": "<YYYY-MM-DD>",
  "createdAt": "<ISO timestamp>",
  "updatedAt": "<ISO timestamp>"
}
```

`seen` starts empty `[]`. `creatorAllowlist`, when set, is an array of handles (e.g., `["jacob", "alice"]`).

Tell the user setup is complete: the screen criteria, budget per buy, and both spend caps. Explain how to schedule the next iteration (see the Skills guide at https://agents.zora.com/guides/agent-skills). Stop.

---

## Iteration Mode

### Step 4: Scan the new feed, screen, and buy

Read `.new-coin-screener-state.json` to get the criteria, `seen` list, and spend counters.

**Reset the daily cap first:** if `spendDate` is not today's calendar date, set `spentToday` to `"0"` and `spendDate` to today.

Scan the global new feed (paginate up to 3 pages to cover recent launches):

```bash
zora explore --sort new --type <criteria.type> --json
```

Collect the `address` (and `creatorHandle` if present) from each result. To get the next page, check `pageInfo.hasNextPage` and pass `pageInfo.endCursor` as `--after`:

```bash
zora explore --sort new --type <criteria.type> --after <endCursor> --json
```

For each coin in the feed whose `address` is **NOT** in `seen`, evaluate the screen (max 5 buys per iteration across the whole feed):

1. **Allowlist gate** — if `creatorAllowlist` is set and the coin's creator handle is not in it, mark the address as seen and skip.
2. Fetch details: `zora get <address> --json` — read `marketCap` and the creator handle.
3. Fetch holders: `zora get holders <address> --json` — count the holders returned (use the top-level `totalHolders` count if present, otherwise the length of the `holders` array; paginate via the top-level `nextCursor` passed as `--after` only if needed to confirm the minimum).
4. **Screen:** the coin passes only if `marketCap >= minMarketCap` AND `holders >= minHolders`.
5. **Mark the address as seen regardless of pass or fail** so it is never re-evaluated.
6. If the coin **fails**, log the reason (`<name>: skipped — market cap $<mc> / <holders> holders`) and move on.
7. If the coin **passes**, attempt to buy (subject to the spend caps below):
   - **Cap check:** if `spentTotal + budget > totalCapEth` OR `spentToday + budget > dailyCapEth`, do NOT buy — log `cap reached` and stop buying for this iteration (you may still finish marking remaining coins as seen).
   - Check spendable ETH: `zora balance --json` (wallet array, entry where `symbol === "ETH"`). Skip if insufficient.
   - Quote first: `zora buy <address> --eth <budget> --quote --json`. If the quote errors (no liquidity, banned coin, etc.), log and skip — do not retry.
   - If the quote looks reasonable, execute: `zora buy <address> --eth <budget> --yes --json`.
   - On success: append an entry to `buys`, add `budget` to both `spentToday` and `spentTotal`, and report creator handle, coin name, market cap, holder count, amount received, and tx hash.

After processing, update state:

- Append every evaluated address (pass or fail) to `seen`
- Persist updated `spentToday`, `spentTotal`, `spendDate`, and the `buys` log
- Update `updatedAt`

Report a summary: coins scanned, coins that passed the screen, trades executed, skipped (with reasons), spend so far today / total against the caps, and errors.

If the feed fails to load, skip the failing page and continue; if no pages load, report the error and stop without changing state.

---

## Manage Mode

### Step 5: Edit criteria or caps

Read `.new-coin-screener-state.json`, present the current criteria and spend counters, and ask the user what to change:

- **Edit criteria** — update `minMarketCap`, `minHolders`, `creatorAllowlist`, `type`, or `budget`
- **Edit caps** — update `dailyCapEth` or `totalCapEth`
- **Reset spend** — set `spentToday` and/or `spentTotal` back to `"0"` (e.g., to start a fresh budget cycle)

Do not clear `seen` here — that prevents re-buying coins already evaluated. Save the updated state and stop.

---

## Global Spending Budget

Beyond this skill's own `dailyCapEth`/`totalCapEth`, the agent may have a **global, wallet-level spending budget** (set with `zora agent budget set`) that caps total spend across _all_ skills. Honor it on every buy:

**Before each buy**, check the global budget with the buy's ETH amount:

```bash
zora agent budget check --eth <amount> --json
```

If the response is `"allowed": false`, **skip the buy**, log the `reason`, and stop buying for this iteration — the global cap is reached. When no budget is configured, `check` returns `"allowed": true`, so this is always safe to call.

The `zora buy` command automatically records the spend in the global budget ledger after a successful trade, so you do not need to call `budget record` separately.

This is on top of — not a replacement for — the spend caps below.

## Safety Guards

- **Max 5 buys per iteration** across the whole feed.
- **Never exceed the daily or total spend cap** — check both before every buy; stop buying once either is reached.
- **Always quote before executing** — skip if the quote fails (this is the liquidity and spam filter).
- **Check spendable ETH** before every trade and keep a gas buffer above zero.
- **Mark every evaluated coin as seen** (pass or fail) so the same coin is never screened or bought twice.
- **Prefer addresses over names** — always buy and look up by `0x` address, never by name.
- **Do not act on stale data** — skip a coin if `zora get` or `zora get holders` returns an error.

## Resetting

Delete `.new-coin-screener-state.json` to start fresh. This clears the `seen` list and spend counters, so previously evaluated coins become eligible again.
