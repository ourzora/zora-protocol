---
"@zoralabs/protocol-sdk": minor
---

Fix premint v2 support in premint client and add support for sepolia to SDK:

- Fix chain constants config for Zora Goerli.
- Support Zora-Sepolia for premint client.
- Fix passing of `config_version` to and from the backend API.
- Change parameter on `makeMintParameters` from `account` to `minterAccount`.
- Fix price minter address for premint client by chain, since it is not the same on all chains (yet).