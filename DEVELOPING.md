# Developer Workflow

## Deploying to a new chain

1. Setup new `chainConfigs` file setting 1. fee recipient, and 2. owner for factory contracts
2. Run forge/foundry deploy script
3. Update deployed addresses file `yarn run update-new-deployment-addresses`
4. Verify `addresses/CHAINID.json` exists.
5. Ensure contracts are verified on block explorer.
7. Add a changeset with `npx changeset`
6. Make PR with new addresses json files and changeset.

# Whats bundled in the published package

* `/package/wagmiGenerated.ts` - smart contract abis and deployment addresses
* `./package/chainConfigs.ts` - configuration of smart contracts by chainId

# Publishing the package; Generating changesets, versioning, building and Publishing.

Diagram of the deploying + publishing workflow:
![Deploying & Publishing Workflow](uml/generated/deployment.svg)

Publishing happens in the following steps:

* Some changes are made to the repo; this can include smart contract changes or additions, if smart contracts are changed, tests should be created or updated to reflect the changes.
* The changes are committed to a branch which is **pushed** to **github**.
* A **pr** is **opened** for this branch.
* The changes are reviewed, if they are **approved**:
* Running the command `npx changeset` will generate **a new changeset** in the `./changesets` directory. This changeset will be used to determine the next version of the bundled packages; this commit should then be pushed.
* Upstack the `release` branch against the branch that is to be released. This will cause a ci job to trigger that creates a `version-packages` branch.
* *If there are changes to the smart contracts that should be deployed* 
  * Check out the `release` branch, deploy the contracts in that branch; 
  * deploying the contract results in the addresses of the deployed contracts being updated in the corresponding `./addresses/{chainId}.json` file. This file should be committed and pushed to github.
  * create a minor version bump changeset, and commit it (`npx changeset`)
  * `version-packages` pr will be updated
* Merge `version-packages` onto `release` branch, the package is the published to npm with the command: `yarn publish-packages` and the package is published to npm, with the version specified in the changeset; a release is added to github with the changeset message.
* Merge `release` into main to have the current version in main.