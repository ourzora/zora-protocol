---
name: dca
description: Dollar-cost-average into a chosen set of coins. On first invocation, collects the coin list, per-buy USD amount, optional caps, and which token to spend. Each subsequent invocation buys a fixed USD amount of every coin still under its cap.
compatibility: Requires the Zora CLI (@zoralabs/cli).
---

# Dollar-Cost Averager (DCA) Skill

**Skill version 1.0.0**

## What This Skill Does

You are a Zora dollar-cost-averaging agent. Your job is to steadily accumulate a chosen set of coins by buying a fixed USD amount of each on every iteration, respecting per-coin and overall budget caps. The skill runs **one iteration per invocation**: on the first run it collects the coin list and budget config, and each subsequent run places one round of buys. To run on a schedule (e.g. one buy per coin per day), use the agent's native scheduler (e.g. Claude Code's `/loop`; see the Skills guide at https://agents.zora.com/guides/agent-skills).

## Requirements

Before starting, make sure you have the Zora CLI basics — if they're not already in your context, use the core Zora CLI skill, installed alongside this one as `zora-cli` (how to invoke the CLI, response shapes, error handling). Commands below use `zora` as shorthand for `npx @zoralabs/cli@latest`. Always use `--json` and check for `"error"` in responses.

## Step 1: Determine mode

Check if `.dca-state.json` exists in the working directory.

- **File missing** → Setup Mode (Steps 2–3)
- **File exists** → ask the user what they want to do:
  - **Buy** → Iteration Mode (Step 4)
  - **Add** / **Remove** / **Edit** coins or caps → Manage Mode (Step 5)

---

## Setup Mode

### Step 2: Collect configuration

Ask the user:

1. **Coins to DCA into** — a list of coins, **addresses preferred** (`0x...`) over names to avoid coin-type ambiguity. If the user gives names, resolve each to an address first (`zora get creator-coin <handle> --json`, `zora get trend <ticker> --json`, or `zora explore --json`) and confirm the match.
2. **Per-buy USD amount** — the USD value to buy of each coin, per iteration (e.g. `5` for $5 per coin per run). The user can set a different amount per coin.
3. **Per-coin budget cap** (optional) — the total USD to ever spend on that coin (`null` for no cap). Once a coin's cumulative spend reaches its cap, it stops being bought.
4. **Overall budget cap** (optional) — the total USD to ever spend across all coins combined (`null` for no cap).
5. **Spend token** — which token to spend: `eth` (default), `usdc`, or `zora`.

Validate the setup before saving:

```bash
zora wallet info --json
zora balance --json
zora get <address> --json   # for each coin, confirm it resolves
```

Show the user their wallet address and spendable balance (from the `wallet` array, matching the chosen spend token's `symbol`). Fail fast on any error.

### Step 3: Save state

Save `.dca-state.json`:

```json
{
  "spendToken": "eth",
  "coins": [
    {
      "address": "0x...",
      "name": "coin-name",
      "perBuyUsd": 5,
      "cap": 100,
      "spent": 0,
      "buys": []
    }
  ],
  "overallCap": 500,
  "overallSpent": 0,
  "createdAt": "<ISO timestamp>",
  "updatedAt": "<ISO timestamp>"
}
```

`cap` and `overallCap` may be `null` (no cap). Each entry in a coin's `buys` array looks like:

```json
{ "usd": 5, "txHash": "0x...", "timestamp": "<ISO timestamp>" }
```

Show the config summary (coins, per-buy amounts, caps, spend token) and explain how to schedule the next iteration (see the Skills guide at https://agents.zora.com/guides/agent-skills). Stop.

---

## Iteration Mode

### Step 4: Place one round of buys

Read `.dca-state.json` to get `spendToken`, `coins`, `overallCap`, and `overallSpent`.

Check spendable balance first:

```bash
zora balance --json
```

Read the `wallet` entry whose `symbol` matches the spend token (`ETH`, `USDC`, or `ZORA`). If the balance is too low to cover a buy, report it and stop without buying.

For each coin in `coins`, in order:

1. **Skip if at cap** — if `cap` is a positive number and `spent >= cap`, log `<name>: cap reached ($<spent> / $<cap>), skipping` and move on.
2. **Respect the overall cap** — if `overallCap` is a positive number and `overallSpent + perBuyUsd > overallCap`, log that the overall cap would be exceeded and stop placing further buys this iteration.
3. **Clamp to the remaining cap** — if `cap` is set and `spent + perBuyUsd > cap`, reduce this buy to `cap - spent` so the cap is hit exactly.
4. **Buy** the USD amount:
   - Default spend token: `zora buy <address> --usd <amount> --yes --json`
   - Otherwise add the token flag: `zora buy <address> --usd <amount> --token usdc --yes --json` (or `--token zora`)
5. **Check for `error`** in the response. **Do NOT count a buy as spent if it errored** — leave `spent` unchanged and report the failure so the next iteration retries.
6. **On success**, append `{ usd: <amount>, txHash: <transactionHash>, timestamp: <now> }` to the coin's `buys`, add `<amount>` to that coin's `spent`, and add `<amount>` to `overallSpent`. Report coin name, USD bought, amount received, and tx hash.

After processing all coins, update `updatedAt` and save state.

If every coin has reached its cap (or the overall cap is reached), report that all caps are reached and tell the user they can **stop scheduling** further iterations.

Report a summary: coins bought this iteration, USD spent this iteration, total spent per coin vs cap, overall spent vs overall cap, and any errors.

---

## Manage Mode

### Step 5: Add, remove, or edit coins and caps

Read `.dca-state.json`, present the current config (coins, per-buy amounts, spent vs cap, spend token, overall cap), and ask the user what to change:

- **Add** — same flow as Setup Step 2 for new coins (resolve to address, set `perBuyUsd` and `cap`, start `spent: 0` with an empty `buys` array), append to `coins`
- **Remove** — ask which coin(s) to drop
- **Edit** — update `perBuyUsd`, `cap`, `overallCap`, or `spendToken`; never reset `spent` or `buys` unless the user explicitly asks (it tracks real money already spent)

Save the updated state and stop.

---

## Global Spending Budget

Beyond this skill's own per-coin and overall caps, the agent may have a **global, wallet-level spending budget** (set with `zora agent budget set`) that caps total spend across _all_ skills. Honor it on every buy:

**Before each buy**, check the global budget with the buy's USD amount:

```bash
zora agent budget check --usd <amount> --json
```

If the response is `"allowed": false`, **skip the buy**, log the `reason`, and stop buying for this iteration — the global cap is reached. When no budget is configured, `check` returns `"allowed": true`, so this is always safe to call.

The `zora buy` command automatically records the spend in the global budget ledger after a successful trade, so you do not need to call `budget record` separately.

This is on top of — not a replacement for — the per-coin and overall caps below.

## Safety Guards

- **Check for `error` before counting a buy as spent** — never add to `spent` / `overallSpent` on a failed buy; let the next iteration retry.
- **Never exceed caps** — skip coins at their cap, clamp the final buy to land exactly on the cap, and stop the round before the overall cap is breached.
- **Prefer addresses over names** — resolve names to `0x` addresses at setup to avoid buying the wrong coin type.
- **Check spendable balance** before buying and stop if the spend token runs low.
- **Read commands lag writes** — after a confirmed buy, `balance` may take a few seconds to reflect it; rely on the recorded `spent` in state for cap math, not a fresh balance read.

## Resetting

Delete `.dca-state.json` to start fresh. This also clears the recorded spend history — past buys still happened on-chain, so re-running from zero will ignore prior spend against caps.
