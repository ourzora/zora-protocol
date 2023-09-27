import { Address, LocalAccount, PublicClient, encodeDeployData, encodeFunctionData } from "viem"
import { iImmutableCreate2FactoryABI, iImmutableCreate2FactoryAddress, newFactoryProxyDeployerABI } from "./wagmiGenerated";
import { newFactoryDeployerCreationCode } from "./deploymentConfig";
import { zoraTestnet } from "viem/chains";

type ConfiguredSalt = `0x${string}`;

// Load environment variables from `.env.local`
export type DeterminsticDeploymentConfig = {
  deployerAddress: Address,
  factoryDeloyerSalt: ConfiguredSalt,
  proxyShimSalt: ConfiguredSalt,
  factoryProxySalt: ConfiguredSalt,
  expectedFactoryProxyAddress: Address,
}

export type DeployedContracts = {
  factoryImplAddress: Address,
}

export const getDeployFactoryProxyDeterminsticTx = async ({
  publicClient,
  account,
  determinsticDeploymentConfig: config,
  factoryImplAddress,
  factoryOwner,
}: {
  account: LocalAccount,
  publicClient: PublicClient,
  determinsticDeploymentConfig: DeterminsticDeploymentConfig,
  factoryImplAddress: Address,
  factoryOwner: Address,
}) => {
  const initCode = encodeDeployData({
    abi: newFactoryProxyDeployerABI,
    bytecode: newFactoryDeployerCreationCode,
    args: [
      config.deployerAddress
    ]
  });


  // execute transaction to create the factory deployer determinstically
  const createTransaction = await account.signTransaction({
    to: iImmutableCreate2FactoryAddress[zoraTestnet.id],
    data: encodeFunctionData({
      abi: iImmutableCreate2FactoryABI,
      functionName: 'safeCreate2',
      args: [
        config.factoryDeloyerSalt,
        initCode
      ]
    }),
    chainId: zoraTestnet.id,
    type: 'eip2930'
  });

  // call immutable create 2
  const factoryDeployerAddress = await publicClient.readContract({
    abi: iImmutableCreate2FactoryABI,
    address: iImmutableCreate2FactoryAddress[zoraTestnet.id],
    functionName: "findCreate2Address",
    args: [
      config.factoryDeloyerSalt,
      initCode
    ]
  });


  // now call the new factory deployer to initialize the contract and transfer ownership
  const initializeTx = await account.signTransaction({
    to: factoryDeployerAddress,
    data: encodeFunctionData({
      abi: newFactoryProxyDeployerABI,
      functionName: 'createAndInitializeNewFactoryProxyDeterminstic',
      args: [
        config.proxyShimSalt,
        config.factoryProxySalt,
        config.expectedFactoryProxyAddress,
        factoryImplAddress,
        factoryOwner
      ]
    }),
    chainId: zoraTestnet.id,
    type: 'eip2930'
  });

  return {
    createTransaction,
    initializeTx
  };
}
