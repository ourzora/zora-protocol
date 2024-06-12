---
"@zoralabs/protocol-sdk": minor
---

- new high-level sdks: `createCreatorClient` and `createCollectorClient`. `createPremintClient`, `createMintClient` and `create1155CreatorClient` are deprecated.
- external apis, such as the premint api can be stubbed/replaced/mocked.
- new function `mint` on the collector sdk that works with `1155`, `premint`, and `721`s.
- `create1155` now supports creating erc20, free, and paid mints. Setup actions now mimic what's on zora.co.
