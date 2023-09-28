import { Address, LocalAccount } from "viem";

export type ConfiguredSalt = `0x${string}`;
// Load environment variables from `.env.local`
export type DeterminsticDeploymentConfig = {
  proxyDeployerAddress: Address;
  proxyShimSalt: ConfiguredSalt;
  proxySalt: ConfiguredSalt;
  proxyCreationCode: `0x${string}`;
};

export type DeployedContracts = {
  factoryImplAddress: Address;
};

export const signDeployFactory = ({
  account,
  determinsticDeploymentConfig: config,
  implementationAddress,
  owner,
  chainId,
}: {
  account: LocalAccount;
  determinsticDeploymentConfig: DeterminsticDeploymentConfig;
  implementationAddress: Address;
  owner: Address;
  chainId: number;
}) =>
  account.signTypedData({
    types: {
      createProxy: [
        { name: "proxyShimSalt", type: "bytes32" },
        { name: "proxySalt", type: "bytes32" },
        { name: "proxyCreationCode", type: "bytes"},
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
      name: "NewFactoryProxyDeployer",
      version: "1",
      verifyingContract: config.proxyDeployerAddress,
    },
  });
