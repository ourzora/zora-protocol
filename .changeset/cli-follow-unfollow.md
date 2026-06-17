---
"@zoralabs/cli": minor
---

Add `zora follow <user>` and `zora unfollow <user>` to follow and unfollow other Zora users from the CLI. The target can be a username (with or without a leading `@`), a wallet address, or an account id. Both commands sign in with the configured wallet's Privy session and report the resulting relationship — including when the follow is mutual — and support `--json`.

Following a profile requires holding that profile's creator coin: `zora follow` checks the balance first and, when none is held, points to `zora buy` for the right coin instead of following. Unfollowing is never gated.
