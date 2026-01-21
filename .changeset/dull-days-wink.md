---
"@zoralabs/protocol-deployments": minor
---

Add dev contract exports for Base mainnet development deployments

- Add `devCoinFactoryAddress` and `devCoinFactoryABI` exports for dev Coin factory
- Add `devZoraLimitOrderBookAddress` and `devZoraLimitOrderBookABI` exports for dev limit order book
- Add `devZoraRouterAddress` and `devZoraRouterABI` exports for dev router
- Add `devBuySupplyWithSwapRouterHookABI` export (address empty due to zero address in deployment)
- Fix bug in getLimitOrdersContracts that was not filtering out dev files
