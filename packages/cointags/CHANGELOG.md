# @zoralabs/cointags-contracts

## 0.1.2

### Patch Changes

- 066c289a: Ensure that cointags can only be created with v3 Uniswap pools

## 0.1.1

### Patch Changes

- 5da3d1b0: Removed transient storage as it's no longer used
- 9ccd40bb: Update cointags with erc7201 storage slots for contract variables

## 0.1.0

### Patch Changes

- 1bc855fd: Don't revert buyburn if transfer to dead address fails
- 669c1834: Added upgrade gate and upgradeability to the cointag contract
- 1bc855fd: Recover if transferring erc20s to dead addresses reverts
- f2e523f3: Removed TWAP based slippage protection
- f30466a8: feat: add check to validate one token in the uniswap pool must be WETH
- 036b69e8: Allow direct ETH deposits via the receive() - allowing deposit to happen separately from pull() and eth to be deposited by anyone.

## 0.0.2

### Patch Changes

- dc84793a:
  - Set TWAP period to be 10 minutes
  - Safe transfer of WETH in swap callback
  - Fix burn error handling weth distribution
- 9b1bb9d1: Using transient storage variable for isPulling
