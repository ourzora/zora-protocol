---
"@zoralabs/cli": minor
---

Add `zora agent connect-email` to link an email to an existing Zora agent account.

`zora agent connect-email` attaches an email address to the Privy account behind an agent's wallet. It signs the wallet in with Sign-In-With-Ethereum (resolving the EOA from `--private-key`, `ZORA_PRIVATE_KEY`, the saved CLI wallet, or a freshly generated one — the same as `zora agent create`), sends a one-time code to the address, and links the email once the code is entered. Provide the address with `--email` or enter it when prompted. If the email is already linked to the account, the command reports that and makes no changes. Because verifying the emailed code is interactive, this command cannot run with `--yes`.
