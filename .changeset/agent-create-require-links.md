---
"@zoralabs/cli": patch
---

Always report the profile and first-post links after `zora agent create` finishes. The first-post link previously depended on resolving the content-coin address from the inline `submitUserOperation` logs, which are routinely empty under headless/CI runs — so the post link was almost never shown. The address is now also resolved from the mined transaction's receipt, and falls back to the agent's profile URL when it still can't be pinned down, so a link is always available.

The creator-coin and first-post steps are also now best-effort: once the account (Privy login, profile, and smart wallet) exists, a failure in either step no longer discards the result, so the profile link is still reported (with the failure noted) instead of the command erroring out with no output.
