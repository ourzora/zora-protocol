---
"@zoralabs/coins": patch
---

Fix ETH transfer failures in reward distribution when platform referrers cannot accept ETH

- Prevent swaps from reverting when platform referrers cannot accept ETH - in this case, the rewards are redirected to the protocol recipient as backup.
- Ensures coin functionality remains intact even with ETH-incompatible platform referrers
