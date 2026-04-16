---
"@zoralabs/cli": minor
---

Add tabbed live view to `zora get` and move `price-history` under it

- `zora get <address-or-name>` now shows an interactive live view with a pinned coin summary and tabbed detail panels (Price History), matching the `zora profile` interaction pattern
- `zora get price-history <address-or-name>` replaces the standalone `zora price-history` command
- Ambiguous coin names (matching both a creator-coin and a trend) now error with a suggestion to specify the type, instead of showing both results
