import { Address, LocalAccount } from "viem";

export type ConfiguredSalt = `0x${string}`;
// Load environment variables from `.env.local`
export type DeterminsticDeploymentConfig = {
  factoryDeployerAddress: Address;
  proxyShimSalt: ConfiguredSalt;
  factoryProxySalt: ConfiguredSalt;
};

export type DeployedContracts = {
  factoryImplAddress: Address;
};

export const signDeployFactory = ({
  account,
  determinsticDeploymentConfig: config,
  factoryImplAddress,
  factoryOwner,
  chainId,
}: {
  account: LocalAccount;
  determinsticDeploymentConfig: DeterminsticDeploymentConfig;
  factoryImplAddress: Address;
  factoryOwner: Address;
  chainId: number;
}) =>
  account.signTypedData({
    types: {
      createFactoryProxy: [
        { name: "proxyShimSalt", type: "bytes32" },
        { name: "factoryProxySalt", type: "bytes32" },
        { name: "factoryImplAddress", type: "address" },
        { name: "owner", type: "address" },
      ],
    },
    message: {
      proxyShimSalt: config.proxyShimSalt,
      factoryImplAddress,
      factoryProxySalt: config.factoryProxySalt,
      owner: factoryOwner,
    },
    primaryType: "createFactoryProxy",
    domain: {
      chainId,
      name: "NewFactoryProxyDeployer",
      version: "1",
      verifyingContract: config.factoryDeployerAddress,
    },
  });
