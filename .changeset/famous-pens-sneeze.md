---
"@zoralabs/coins": minor
---

Remove Uniswap V3 support and refactor coin architecture

**Removal of V3 Support:**
- Removed V3-specific test files and utilities
- Updated remaining tests to use V4 deployment methods  
- Removed V3 configuration functions and encoders
- Added revert logic for V3 deployment attempts

**Architecture Refactoring:**
- Merged BaseCoinV4 functionality into BaseCoin.sol to consolidate Uniswap V4 integration
- Combined ICoinV4 interface with ICoin interface to simplify the interface hierarchy
- Updated ContentCoin and CreatorCoin to inherit directly from BaseCoin
- Removed duplicate files: BaseCoinV4.sol and ICoinV4.sol
- Updated all imports and references throughout the codebase
- This is an internal refactoring that doesn't change external functionality