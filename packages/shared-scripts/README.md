# Zora Shared Deployment Scripts

Reusable scripts for when deploying of Zora contracts.

## `update-contract-version`

Updates the `contractVersion` in the `ContractVersionBase.sol` file to the correct version; must be run from within the package directory:

```bash
cd packages/erc20z
pnpm exec update-contract-version
```

## `sign-deploy-and-call-with-turnkey`

Signs a deploy and call transaction with Turnkey. Meant to be used in conjunction with the `ProxyDeployerScript`.

## `bundle-abis`

Bundles the ABIs for a given package into a single file. Meant to be used in conjunction with the `build` script.

```bash
cd packages/erc20z
pnpm exec bundle-abis
```
