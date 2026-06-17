---
"@zoralabs/cli": minor
---

Add `zora dm listen` for real-time DM streaming

Opens a long-lived XMTP server-push stream so agents receive DMs as they arrive instead of polling, avoiding XMTP read rate limits during continuous monitoring.
