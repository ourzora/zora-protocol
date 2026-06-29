---
"@zoralabs/cli": minor
---

Add `zora coin edit` to edit a post's image and/or description (caption) from the CLI.

Mirrors the Zora app's "Edit post": it fetches the coin's current metadata, applies the changes, re-uploads the metadata to IPFS, and updates the coin's `contractURI` on-chain. The name/ticker is kept fixed (as the app does for coins), and only the coin's creator can edit it. Accepts a coin address or a creator/trend name; pass `--image`, `--description`, or both — whatever is omitted is preserved. No backend changes are required (this wires up the published `updateCoinURI`/`updateCoinURISmartWallet` actions from `@zoralabs/coins-sdk`).
