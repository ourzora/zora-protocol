---
"@zoralabs/coins": minor
---

Enable buying initial supply when deploying creator coin and refactor factory internals

- Add new `deployCreatorCoin` overload with `postDeployHook` parameter that supports ETH transfers
- Refactored internal factory implementation to share more code between deployment methods
- Enables buying initial supply during creator coin deployment via post-deploy hooks