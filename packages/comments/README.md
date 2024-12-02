# Comments

## Deployment

The `Comments` contract is deployed deterministically using a turnkey account. The deployment process uses a helper contract, [DeterministicDeployerAndCaller](../../packages/shared-contracts/src/deployment/DeterministicDeployerAndCaller.sol).

### Prerequisites

- Ensure you have [Forge](https://book.getfoundry.sh/getting-started/installation) installed.
- Familiarity with [turnkey accounts](https://docs.turnkey.com/) is recommended.

### Setting up environment variables

In the `packages/comments` directory:

1. Copy `.env.example` to `.env`
2. Populate the parameters in `.env`

### Deploying the Comments Contracts

1. Deploy the `Comments` contract, you must pass the `--ffi` flag to enable calling an external script to sign the deployment with turnkey:

```bash
forge script script/Deploy.s.sol $(chains {chainName} --deploy) --broadcast --verify --ffi
```

where `{chainName}` is the emdash name of the chain you want to deploy on.

2. Verify the proxy contracts. Since they are deployed with create2, foundry wont always recognize the deployed contract, so verification needs to happen manually:

for the comments contract:

```bash
forge verify-contract 0x7777777C2B3132e03a65721a41745C07170a5877 Comments $(chains {chainName} --verify) --constructor-args 0x000000000000000000000000064de410ce7aba82396332c5837b4c6b96108283
```

for the caller and commenter contract:

```bash
forge verify-contract 0x77777775C5074b74540d9cC63Dd840A8c692B4B5 CallerAndCommenter $(chains {chainName} --verify) --constructor-args 0x000000000000000000000000064de410ce7aba82396332c5837b4c6b96108283
```
