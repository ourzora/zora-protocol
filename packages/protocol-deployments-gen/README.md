# Protocol Deployments Codegen

This is an internal package meant to generate code for use in `protocol-deployments`.
It pulls in abis and addresses from relevant packages in the monorepo, and bundles them
into a file in `protocol-deployments`. The reason to have it as a separate package
is to avoid `protocol-deployments` having dependencies to internal/non-published packages.

## Common Patterns and Examples

This section documents common patterns used in this package's `wagmi.config.ts` file for handling different types of contracts and deployment scenarios.

### Pattern 1: Factory Contract with Implementation

Many packages follow a factory + implementation pattern:

```typescript
// Both contracts get addresses from the same address files
addAddress({
  abi: factoryImplABI,
  addresses,
  configKey: "YOUR_FACTORY",
  contractName: "YourFactory",
  storedConfigs,
});

addAddress({
  abi: implementationABI,
  addresses,
  configKey: "YOUR_IMPL",  // Different key, same address file
  contractName: "YourImplementation", 
  storedConfigs,
});
```

### Pattern 2: Interface + Implementation

Combine ABI-only interfaces with deployed implementations:

```typescript
return [
  ...toConfig(addresses), // Address-based contracts
  {
    abi: iYourInterfaceABI,
    name: "IYourInterface",  // Interface without addresses
  },
  {
    abi: yourImplementationABI,
    name: "YourImplementation", // Implementation with addresses
  },
];
```

### Pattern 3: Development vs Production Addresses

Handle different address sets for development:

```typescript
// Load production addresses
const storedConfigs = addressesFiles.map((file) => ({
  chainId: parseInt(file.split(".")[0]),
  config: JSON.parse(readFileSync(`../your-package/addresses/${file}`, "utf-8")),
}));

// Load development addresses  
const devConfigs = devAddressesFiles.map((file) => ({
  chainId: parseInt(file.split(".")[0]),
  config: JSON.parse(readFileSync(`../your-package/addresses/dev/${file}`, "utf-8")),
}));

// Create separate entries for dev and production
addAddress({
  contractName: "YourContract",
  storedConfigs,  // Production addresses
  // ... other config
});

addAddress({
  contractName: "DevYourContract", 
  storedConfigs: devConfigs,  // Development addresses
  // ... other config
});
```
