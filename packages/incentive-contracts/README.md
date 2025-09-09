# Incentive

A protocol for managing allocation-based incentive distributions with backend-signed KYC verification and configurable expiry periods.

## Quick Start

This package contains smart contracts for the Zora Incentive protocol supporting:

- Period-based allocation management
- EIP-712 signature verification for KYC compliance
- multiple concurrent periods & single period claiming
- Admin-controlled funding 

### Development Setup

1. **Install dependencies**:

   ```bash
   pnpm install
   ```

2. **Build contracts**:

   ```bash
   forge build
   ```

3. **Run tests**:
   ```bash
   forge test -vvv
   ```

### Testing

- `forge test -vvv` - Run Solidity tests with verbose output
- `forge test --watch -vvv` - Run tests in watch mode
- `forge test -vvv --match-test {test_name}` - Run specific test
- `pnpm test` - Run tests via package script
- `pnpm run test-gas` - Run tests with gas reporting
- `pnpm run coverage` - Generate test coverage report

### Code Quality

- `pnpm run prettier:check` - Check code formatting
- `pnpm run prettier:write` - Format code automatically
- `pnpm run slither` - Run security analysis
- `pnpm run build:sizes` - Check contract sizes

### Prerequisites

- Ensure you have [Forge](https://book.getfoundry.sh/getting-started/installation) installed
