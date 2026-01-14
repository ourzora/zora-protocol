---
"@zoralabs/limit-orders": patch
---

Fix potential hash collision in order ID generation

Changed order ID derivation from `abi.encodePacked` to `abi.encode` to prevent potential hash collisions and ensure consistent hashing behavior. This security fix addresses audit finding MKT-47.