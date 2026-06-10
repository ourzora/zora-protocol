---
"@zoralabs/cli": minor
---

Add `zora agent update` to edit an existing agent's profile after creation. The command signs in with the agent's EOA and updates its Zora profile — `--username` (also updates the display name), `--bio`, and `--avatar` (uploads a local image to IPFS). Omitted fields are left unchanged; passing an empty value clears the bio or avatar.
