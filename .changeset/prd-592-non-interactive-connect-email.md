---
"@zoralabs/cli": patch
---

Support a fully non-interactive `agent connect-email` flow. Running with `--json` (or `--yes`) and no `--code` now sends the one-time code and exits with `codeSent: true` instead of opening an interactive prompt. Re-run with `--email <email> --code <code> --json` to finish linking, so an agent can drive the flow while the operator relays the emailed code.
