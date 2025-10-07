# Hookmate Library

This directory contains the hookmate library for deploying Uniswap V4 infrastructure in non-forked test environments.

## Overview

[Hookmate](https://github.com/akshatmittal/hookmate) provides deployer libraries that wrap contract initcode and constructor arguments, enabling deterministic deployment of V4 contracts without requiring mainnet forks.

## Added Contracts

The following contracts were **not** part of the original hookmate library and were added to support the Zora coins testing infrastructure:

### V4Quoter.sol
- Used for simulating swaps and getting quote amounts
- Added to `artifacts/V4Quoter.sol`

### UniversalRouter.sol
- Handles multi-protocol routing and swap execution
- Added to `artifacts/UniversalRouter.sol`

## How These Contracts Were Added

1. **Extract bytecode** from deployed mainnet contract using Etherscan
2. **Create deployer library** with structure:
   ```solidity
   library ContractNameDeployer {
       function deploy(/* constructor args */) internal returns (address deployed) {
           bytes memory args = abi.encode(/* constructor args */);
           bytes memory initcode_ = abi.encodePacked(initcode(), args);
           deployed = DeployHelper.deploy(initcode_);
       }

       function initcode() internal pure returns (bytes memory) {
           return hex"<bytecode from etherscan>";
       }
   }
   ```
3. **Save to** `artifacts/ContractName.sol`
4. **Import and use** in `BaseTest.sol` or test files

## Adding Future Contracts

To add a new contract to hookmate:

1. Find deployed contract on Etherscan
2. Copy the contract creation bytecode
3. Create new file `artifacts/ContractName.sol` following the pattern above
4. Define constructor parameters struct if needed
5. Implement `deploy()` and `initcode()` functions
6. Test deployment in non-forked environment
