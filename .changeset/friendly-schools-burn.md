---
"@zoralabs/cli": patch
---

Auto-detect coin type on sell when only one is held

- When both a creator-coin and trend share the same name, the sell command now checks the user's balance and auto-selects the one they hold
- If the user holds both or neither, the existing disambiguation error is shown
