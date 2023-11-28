---
"@zoralabs/protocol-sdk": patch
---

premintClient has http methods overridable via dependency injection, and now takes publicClient and http overrides in `createPremintClient` function. it no longer takes `publicClient` as an argument in functions, and rather uses them from the constructor
