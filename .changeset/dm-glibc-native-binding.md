---
"@zoralabs/cli": patch
---

Fix `zora dm` not working on common Linux servers (glibc too old)

DMs use a native module whose default prebuilt Linux binary requires glibc 2.38 —
newer than Ubuntu 22.04, Debian 12, the default node:20/22/24 images, and many
GCP/VPS hosts. On those systems `zora dm` crashed with a cryptic, misleading error.

The CLI now selects the right XMTP build for the host at runtime: the default SDK
on musl (Alpine), macOS, Windows, and recent glibc, and a matched low-glibc build
on older-glibc Linux. DMs work out of the box on musl/macOS/Windows/new-glibc at
any Node version, and on older-glibc Linux when running **Node 22+** (the low-glibc
build requires Node 22+). When the low-glibc build can't be used — Node 20 on old
glibc, or the build is unavailable — the CLI shows a clear, actionable message
(run on Alpine, use Node 22+, or a glibc ≥ 2.38 image) instead of crashing.
