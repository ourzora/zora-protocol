# Developer Workflow

## Deploying to a new chain

Within a contracts package folder (i.e. `packages/1155-contracts`):

1. Setup new `chainConfigs` file setting 1. fee recipient, and 2. owner for factory contracts
2. Generate signatures for deploying the upgrade gate at a deterministic address and transferring ownership to the factory owner:

    yarn tsx script/signDeploymentTransactions.ts

3. Deploy upgrade gate and implementation contracts:

    forge script script/DeployMintersAndImplementations.s.sol  $(chains {CHAINNAME} --deploy) --interactives 1 --broadcast --verify

4. Copy deployed addresses to `addresses/{CHAINID}.json`:

    yarn tsx script/copy-deployed-contracts.ts

5. Generate signatures to deploy proxy contracts at deterministic address:

    yarn tsx script/signDeploymentTransactions.ts

6. Deploy proxy contracts:

    forge script script/DeployProxiesToNewChain.s.sol  $(chains {CHAINNAME} --deploy) --interactives 1 --broadcast --verify

7. Ensure contracts are verified on block explorer.
8. Add a changeset with `yarn changeset`
9. Make PR with new addresses json files and changeset.

# Publishing the package; Generating changesets, versioning, building and Publishing.

Publishing happens in the following steps:

* Some changes are made to the repo; this can include smart contract changes or additions, if smart contracts are changed, tests should be created or updated to reflect the changes.
* The changes are committed to a branch that is **pushed** to **github**.
* A **pr** is **opened** for this branch.
* The changes are reviewed, if they are **approved**:
* *If there are changes to the smart contracts that should be deployed*: the contract should be. Deploying the contract results in the addresses of the deployed contracts being updated in the corresponding `./addresses/{chainId}.json` file. This file should be committed and pushed to github.
* Running the command `yarn changeset` will generate **a new changeset** in the `./changesets` directory. This changeset will be used to determine the next version of the bundled packages; this commit should then be pushed.
* The changeset and smart contract addresses are pushed to the branch.
* The pr is merged into main - any changesets in the PR are detected by a github action `release`, which will then **open a new PR** with proper versions and readme updated in each each package.   If more changesets are pushed to main before this branch is merged, the PR will continuously update the version of the packages according to the changeset specification.

7. That version is merged into main along with the new versions.

8. The package is then published to npm with the command: `yarn publish-packages` and the package is published.
