---
"@zoralabs/1155-deployments": patch
---

Remove mints-deployments as dependency as it is now directly included in codegen.

This fixes the package not being publish in npm and used only as an internal build package.
