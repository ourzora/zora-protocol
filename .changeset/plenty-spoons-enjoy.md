---
"@zoralabs/limit-orders": patch
---

Initialize max fill count to 50 in ZoraLimitOrderBook constructor

Sets a default maximum fill count of 50 orders per transaction in the constructor, providing consistent behavior from deployment without requiring separate configuration.
