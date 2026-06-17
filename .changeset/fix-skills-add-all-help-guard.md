---
"@zoralabs/cli": minor
---

Fix `skills add --all` and add the `cli` skill to the installable list

`skills add --all` showed help and exited without installing anything. The CLI's help-guard aborted any command that declared a positional argument but received none — but `--all` installs every skill without a name. The `skills add` command is now exempt from that guard, since it validates that exactly one of `--all` or a skill name is provided.

Also adds the umbrella `cli` skill (the agent's full Zora interface) to `skills list` and `skills add`, installable as `zora-cli`. It is served at `https://agents.zora.com/skill/cli.md` alongside the strategy skills.
