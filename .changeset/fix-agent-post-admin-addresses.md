---
"@zoralabs/cli": patch
---

Fix the first-post step of `zora agent create` failing with a server validation error ("expected array, received undefined"). The content-coin creation request must send the agent's admin addresses under the Zora backend's `adminAddressess` field; restore that exact key so the first post is published successfully.
