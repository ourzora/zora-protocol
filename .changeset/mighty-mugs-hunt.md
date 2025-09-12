---
"@zoralabs/coins": minor
---

Adds platform referral and trade referral functionality to creator coins, and unifies the fee structure between content and creator coins with a simplified 1% total fee.

**New Features:**

- Platform referral and trade referral functionality for creator coins (previously only supported on content coins)
- Unified fee structure: Both content and creator coins use identical 1% fee distribution

**Fee Structure Changes:**

**Before (Content Coins - 3% total fee):**
| Recipient       | % of Market Rewards | % of Total Fees |
| --------------- | ------------------- | --------------- |
| Creator         | 50%                 | 33.33%          |
| Create Referral | 15%                 | 10%             |
| Trade Referral  | 15%                 | 10%             |
| Doppler         | 5%                  | 3.33%           |
| Protocol        | 15%                 | 10%             |
| --------------- | ------------------- | --------------- |
| LP Rewards      | -                   | 33.33%          |

**Before (Creator Coins - 3% total fee):**
| Recipient       | % of Market Rewards | % of Total Fees |
| --------------- | ------------------- | --------------- |
| Creator         | 50%                 | 33.33%          |
| Protocol        | 50%                 | 33.33%          |
| --------------- | ------------------- | --------------- |
| LP Rewards      | -                   | 33.33%          |

**After (All Coins - 1% total fee):**
| Recipient         | % of Market Rewards | % of Total Fee |
| ----------------- | ------------------- | -------------- |
| Creator           | 62.5%               | 0.50%          |
| Platform Referral | 25%                 | 0.20%          |
| Trade Referral    | 5%                  | 0.04%          |
| Doppler           | 1.25%               | 0.01%          |
| Protocol          | 6.25%               | 0.05%          |
| ----------------- | ------------------- | -------------- |
| LP Rewards        | -                   | 0.20%          |

**Implementation Changes:**

- Consolidated reward logic into `CoinRewardsV4.distributeMarketRewards()`

**Backwards Compatibility:**

- Existing `CreatorCoinRewards` event is still emitted for backwards compatibility when rewards are distributed for a CreatorCoin
- Additionally, when market rewards are distributed for a CreatorCoin, the same `CoinMarketRewardsV4` event that is already emitted for ContentCoins is now also emitted
