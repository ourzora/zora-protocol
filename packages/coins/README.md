# Coins

## Deployment

The `ZoraFactory` contract is deployed deterministically using a turnkey account. The deployment process uses a helper contract, [DeterministicDeployerAndCaller](../../packages/shared-contracts/src/deployment/DeterministicDeployerAndCaller.sol).

### Prerequisites

- Ensure you have [Forge](https://book.getfoundry.sh/getting-started/installation) installed.
- Familiarity with [turnkey accounts](https://docs.turnkey.com/) is recommended.

### Setting up environment variables

In the `packages/coins` directory:

1. Copy `.env.example` to `.env`
2. Populate the parameters in `.env`

### Deploying the Coins Factory

1. Deploy the `ZoraFactory` contract, you must pass the `--ffi` flag to enable calling an external script to sign the deployment with turnkey:

```bash
forge script script/Deploy.s.sol $(chains {chainName} --deploy) --broadcast --verify --ffi
```

where `{chainName}` is the emdash name of the chain you want to deploy on.

2. Verify the factory contract. Since it is deployed with create2, foundry won't always recognize the deployed contract; verification instructions will be printed out in the logs.
