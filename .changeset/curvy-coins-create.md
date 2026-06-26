---
"@zoralabs/cli": minor
---

Add a `coin` command group with `coin create` for creating a coin (post), and deprecate the top-level `create` command in its favor.

`zora coin create` takes the same flags and behaves identically to the old `zora create`. The `create` command keeps working but now prints a deprecation notice (suppressed in `--json`) directing users to `coin create`, and will be removed in a future release.
