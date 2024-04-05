// config for the determinstic proxy deployer, which should have the same config on all chains.
// this should be the same on all chains
struct ProxyDeployerConfig {
    bytes creationCode;
    bytes32 salt;
    address deployedAddress;
}

struct DeterminsticContractConfig {
    // salt used to determinstically deploy the contract
    bytes32 salt;
    // code to create the contract
    bytes creationCode;
    // expected address
    address deployedAddress;
    // name of the contract, used for verification
    string contractName;
    // constructor args, used for verification
    bytes constructorArgs;
}

// config for deploying the Mints proxy,
// this should be the same on all chains
struct MintsDeterministicConfig {
    // address of the account that is to do the deployment
    address deploymentCaller;
    DeterminsticContractConfig manager;
    DeterminsticContractConfig mints1155;
}

// config by chain, specifying how the transparent proxy is to be initialized
struct TransparentProxyInitializationConfig {
    // admin account that will be able to upgrade the proxy.  should be a multisig
    address proxyAdmin;
    // address of the initial implementation to upgrade the proxy to
    address initialImplementationAddress;
    // abi encoded function call to be invoked on the proxy after setting the initial implementation.  typically an 'initialize' function
    bytes initialImplementationCall;
}
