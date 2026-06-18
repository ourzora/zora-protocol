---
"@zoralabs/cli": patch
---

Temporarily disable skill download integrity verification

Skills are served remotely from agents.zora.com and updated independently of CLI releases, but the integrity check pinned skill content to SHA-256 hashes frozen into each published CLI. As soon as a skill was updated server-side, every already-installed CLI failed the check with a "could indicate a compromised download" error, blocking `zora skills add` for routine updates.

Verification is now gated behind a single flag and turned off so installs work reliably. The hashes and verification path are left in place. A redesign that survives independent skill updates (bundling skills in the package, or signing them and verifying a signature instead of pinning exact content) will re-enable it.
