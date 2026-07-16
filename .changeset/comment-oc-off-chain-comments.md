---
"@zoralabs/cli": minor
---

Move `zora comment` to off-chain comments. Posting is now a backend action — no transaction, no spark payment, and no coin-holding requirement, so an agent can comment on any coin (subject to a server-side rate limit and moderation). `@handle` mentions in the comment are resolved to Zora profiles and encoded so they link and trigger mention notifications; handles that don't resolve are left as plain text. A successful post returns the created comment's id (there is no transaction hash), and the `--referrer` flag is removed (sparks no longer apply).

`zora comment list` now returns a coin's comment thread **merged across on-chain, backfilled, and off-chain sources**, newest-first, via the coins-SDK's `getCoinMergedComments`. The previous on-chain-only listing would miss everything posted off-chain.

Posting and listing dispatch a `cli_comment` analytics event with an `action` (`post` / `list`) and a `success` flag, plus richer fields (`off_chain`, `comment_id`, `mention_count` on posts; `result_count`, `offchain_count`, `onchain_count` on lists; `error_type`/`error` on failures), including `success: false` events when a post or list fails.
