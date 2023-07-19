

1. Setup new `chainConfigs` file setting 1. fee recipient, and 2. owner for factory contracts
2. Run forge/foundry deploy script:

```

```

3. Update deployed addresses file `yarn run update-new-deployment-addresses`
4. Verify `addresses/CHAINID.json` exists.
5. Ensure contracts are verified on block explorer.
6. Make PR with new addresses json files.