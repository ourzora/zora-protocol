---
"@zoralabs/cli": patch
---

Install skills from the CLI bundle instead of fetching them over the network

Skills are now embedded in the published CLI and written to disk on `skills add`, rather than fetched from `agents.zora.com`. This removes the unverified remote-fetch surface (a compromised host or MITM could previously serve poisoned skill instructions) and the version drift that caused installs to fail whenever server-side skill content changed. The installed content is exactly the reviewed source at the commit the CLI was built from.

Installing any strategy skill now also installs the core `zora-cli` skill it depends on, and skills no longer fetch the core skill at runtime. The `--skip-verify` flag and the `ZORA_SKILLS_BASE_URL` override are removed, as there is no longer a download to verify or redirect.
