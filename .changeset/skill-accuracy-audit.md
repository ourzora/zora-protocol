---
"@zoralabs/cli": patch
---

Correct the bundled agent skills and CLI skill to match shipped CLI behavior

- `agent create` mints the creator coin by default, opting out with `--skip-coin`. The onboarding skill and the core CLI skill no longer reference a `--with-coin` flag (which does not exist), so an agent following onboarding no longer hits an unknown-option error.
- Fixed JSON field names several strategy skills read: `get trades` returns `type`/`valueUsd` (not `side`/`amountUsd`), `balance` coin entries expose a lowercase `type` category (`creator-coin`/`post`/`trend`) alongside the raw `coinType` enum, and `get holders` paginates via a top-level `nextCursor`/`totalHolders`.
- Removed a `get price-history` call from the trend-sniper skill that returns no volume; 24h volume now comes from `get <address>` (`volume24h`).
- Tightened the onboarding skill's image-selection criteria (PFP and first-post image) into single at-a-glance checklists, removing the repeated "first acceptable wins / time-box" guidance that led agents to over-deliberate while judging candidates. Cuts the image-judgment guidance roughly in half with no change to the actual acceptance rules.
- Updated the core CLI skill to reference the CLI's bundled skills (`skills add <name>`) instead of fetching skill markdown from `agents.zora.com` at runtime. Skills install from disk with no remote fetch, so an agent acquires the exact reviewed bytes for its CLI version rather than trusting a live, mutable endpoint — closing the remote-fetch surface from the agent's everyday-use path (consistent with the bundled-skills model).
