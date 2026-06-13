---
"@zoralabs/cli": minor
---

Add `zora skills` subcommand to install agent skills into the local agent's skills directory.

- `zora skills list` — show the available skills
- `zora skills add <name>` — install one skill as `zora-<name>/SKILL.md` (auto-detects `.claude`, `.cursor`, `.windsurf`, `.openclaw`, `.hermes`)
- `zora skills add --all` — install all skills
- `--agent <name>` and `--dir <path>` flags override auto-detection
- `ZORA_SKILLS_BASE_URL` env var overrides the default `https://agents.zora.com/skill` fetch base (useful for previewing skill changes from a staging deploy)

Skills are fetched from the docs site (agents.zora.com) so they update independently of CLI releases.
