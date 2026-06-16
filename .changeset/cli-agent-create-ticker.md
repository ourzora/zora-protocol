---
"@zoralabs/cli": patch
---

Add a `--ticker` flag to `zora agent create`'s first post and enforce a title length limit.

Publishing a first post now requires `--ticker <symbol>` (2–20 letters/numbers), validated and rejected before anything is minted instead of silently deriving a symbol. The post coin's title (which defaults to the caption) is capped at 64 characters, so a long caption can be paired with a shorter explicit `--title` while the full caption still renders on the card. The `onboarding` skill now guides authors to pick a ticker and handle long captions during the authoring step.
