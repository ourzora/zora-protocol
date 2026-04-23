---
"@zoralabs/cli": minor
---

Add `zora skills` subcommand to install agent trading skills into the local agent's commands directory.

- `zora skills list` — show the four available skills
- `zora skills add <name>` — install one skill (auto-detects `.claude`, `.cursor`, `.windsurf`)
- `zora skills add --all` — install all skills
- `--agent <name>` and `--dir <path>` flags override auto-detection
- `ZORA_SKILLS_BASE_URL` env var overrides the default `https://zoraskills.dev/skill` fetch base (useful for previewing skill changes from a staging deploy)

Skills are fetched from zoraskills.dev so they update independently of CLI releases.
