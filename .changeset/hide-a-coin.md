---
"@zoralabs/cli": minor
---

Add `zora coin hide` and `zora coin unhide` to hide a coin (e.g. an unwanted airdrop or spam) from your holdings and profile across Zora, or reverse it.

Hiding is a personal preference scoped to your account — it doesn't move or burn the coin, and there's no holding requirement. Accepts a coin address or a creator/trend name. This wires up Zora's existing `addHiddenCreation`/`removeHiddenCreation` mutations (the same hide the Zora app applies), so no backend changes are required.
