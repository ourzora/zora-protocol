---
"@zoralabs/cli": patch
---

Guard destructive commands against silently wrecking an agent setup

`zora agent create` anchors an agent's whole identity on the EOA in `wallet.json` — that key is an owner of the agent's smart wallet, so replacing it permanently orphans the account (coins, posts, and profile included). The wallet commands were built for a disposable human hot wallet and would overwrite that key without warning.

Now, when a wallet belongs to an agent:

- `zora setup` and `zora wallet configure` refuse to overwrite it non-interactively, and otherwise require an explicit confirmation that names the agent and explains the consequences. A plain `--force` no longer bypasses this.
- Re-running `zora agent create` on an existing agent confirms first, since it mints another creator coin and post.
- `zora agent update --username` confirms before changing an established agent's public handle.
- Replacing the stored key drops the now-stale recorded agent identity so the wallet file can't describe an agent it no longer controls.
