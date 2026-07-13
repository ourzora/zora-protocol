---
"@zoralabs/cli": minor
---

Real-time DM handling for agents. `zora dm listen` now surfaces message **requests** (first messages from strangers) distinctly from ongoing DMs, and adds `--exec "<cmd>"` to run a command for each new message — with the message JSON in `$ZORA_DM` — so a turn-based agent is woken the instant a DM or request arrives instead of waiting for its next poll. The listener runs as its own XMTP installation, so it never conflicts with the one-shot `dm send`/`dm approve` commands used to respond, and only one listener runs per machine. Replying to or approving a request now works reliably even when it first arrived on the background listener.

Each `--exec` payload also carries recent thread history so a per-message agent turn has the conversation, not just the latest line — the last 30 minutes of messages by default (tune with `--exec-history <window>`). When a thread has been idle past that window, it falls back to the tail of the previous conversation and reports how long it's been (`hoursSinceLastMessage`), so the agent can treat a returning contact as a fresh conversation rather than a mid-thread reply.
