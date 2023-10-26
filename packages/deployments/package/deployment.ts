import { Address, LocalAccount, Hex } from "viem";

export type ConfiguredSalt = `0x${string}`;
// Load environment variables from `.env.local`
export type DeterministicDeploymentConfig = {
  proxyDeployerAddress: Address;
  proxyShimSalt: ConfiguredSalt;
  proxySalt: ConfiguredSalt;
  proxyCreationCode: Hex;
};

export type GenericDeploymentConfiguration = {
  creationCode: Hex;
  salt: Hex;
  deployerAddress: Address;
  upgradeGateAddress: Address;
  proxyDeployerAddress: Address;
};

export type DeployedContracts = {
  factoryImplAddress: Address;
};

export const signDeployFactory = ({
  account,
  deterministicDeploymentConfig: config,
  implementationAddress,
  owner,
  chainId,
}: {
  account: LocalAccount;
  deterministicDeploymentConfig: DeterministicDeploymentConfig;
  implementationAddress: Address;
  owner: Address;
  chainId: number;
}) =>
  account.signTypedData({
    types: {
      createProxy: [
        { name: "proxyShimSalt", type: "bytes32" },
        { name: "proxySalt", type: "bytes32" },
        { name: "proxyCreationCode", type: "bytes" },
        { name: "implementationAddress", type: "address" },
        { name: "owner", type: "address" },
      ],
    },
    message: {
      proxyShimSalt: config.proxyShimSalt,
      implementationAddress,
      proxyCreationCode: config.proxyCreationCode,
      proxySalt: config.proxySalt,
      owner: owner,
    },
    primaryType: "createProxy",
    domain: {
      chainId,
      name: "DeterministicProxyDeployer",
      version: "1",
      verifyingContract: config.proxyDeployerAddress,
    },
  });

export const signGenericDeploy = ({
  account,
  config,
  chainId,
  initCall,
}: {
  account: LocalAccount;
  config: GenericDeploymentConfiguration;
  initCall: Hex;
  chainId: number;
}) =>
  account.signTypedData({
    types: {
      createGenericContract: [
        { name: "salt", type: "bytes32" },
        { name: "creationCode", type: "bytes" },
        { name: "initCall", type: "bytes" },
      ],
    },
    message: {
      salt: config.salt,
      creationCode: config.creationCode,
      initCall,
    },
    primaryType: "createGenericContract",
    domain: {
      chainId,
      name: "DeterministicProxyDeployer",
      version: "1",
      verifyingContract: config.proxyDeployerAddress,
    },
  });
