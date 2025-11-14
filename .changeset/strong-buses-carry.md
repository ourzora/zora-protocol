---
"@zoralabs/coins": patch
---

Fix incorrect senderIsTrusted logic for address(0) in ZoraV4CoinHook

Removes the special case handling for address(0) in the \_getOriginalMsgSender function that was incorrectly setting senderIsTrusted to true. This behavior was unintentionally changed in commit 09fb2528 which added special handling for address(0). This fix restores the original behavior where address(0) returns false for senderIsTrusted, 
