---
"@zoralabs/limit-orders": patch
---

Remove duplicate validateOrderInputs call in handleCreateCallback

Eliminates redundant validation that was occurring in both _prepareCreateData and handleCreateCallback functions, reducing gas costs while maintaining input validation security.