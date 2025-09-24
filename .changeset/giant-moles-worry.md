---
"@zoralabs/coins": patch
---

Adjust creator coin vesting duration to account for leap years

- Changed CREATOR_VESTING_DURATION from 5 * 365 days to 5 * 365.25 days
- Addresses Cantina audit finding about 1.25 day shortfall in 5-year vesting period