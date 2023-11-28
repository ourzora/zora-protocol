---
"@zoralabs/protocol-sdk": patch
---

premintClient can have http methods overridable via DI, and now takes publicClient and http overrides in `createPremintClient` function. it no longer takes `publicClient` as an argument in functions, and rather uses them from the constructor.  `executePremint` has been renamed ot `makeMintParameters`
