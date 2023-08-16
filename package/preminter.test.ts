import {
  createTestClient,
  http,
  createWalletClient,
  createPublicClient,
} from "viem";
import { foundry, zoraTestnet } from "viem/chains";
import { describe, it, beforeEach, expect } from "vitest";
import { parseEther } from "viem";
import {
  zoraCreator1155PremintExecutorABI as preminterAbi,
  zoraCreator1155ImplABI,
  zoraCreator1155FactoryImplConfig,
  zoraCreator1155PremintExecutorAddress,
  zoraCreator1155FactoryImplAddress,
} from "./wagmiGenerated";
import ZoraCreator1155Attribution from "../out/ZoraCreator1155Attribution.sol/ZoraCreator1155Attribution.json";
import zoraCreator1155PremintExecutor from "../out/ZoraCreator1155PremintExecutor.sol/ZoraCreator1155PremintExecutor.json";
import zoraCreator1155Impl from "../out/ZoraCreator1155Impl.sol/ZoraCreator1155Impl.json";
import zoraCreator1155FactoryImpl from "../out/ZoraCreator1155FactoryImpl.sol/ZoraCreator1155FactoryImpl.json";
import zoraCreatorFixedPriceSaleStrategy from "../out/ZoraCreatorFixedPriceSaleStrategy.sol/ZoraCreatorFixedPriceSaleStrategy.json";
import protocolRewards from "../out/ProtocolRewards.sol/ProtocolRewards.json";
import {
  ContractCreationConfig,
  PremintConfig,
  TokenCreationConfig,
  preminterTypedDataDefinition,
} from "./preminter";
import { chainConfigs } from "./chainConfigs";

const walletClient = createWalletClient({
  chain: foundry,
  transport: http(),
});

export const walletClientWithAccount = createWalletClient({
  chain: foundry,
  transport: http(),
});

const testClient = createTestClient({
  chain: foundry,
  mode: "anvil",
  transport: http(),
});

const publicClient = createPublicClient({
  chain: foundry,
  transport: http(),
});

type Address = `0x${string}`;

const zeroAddress: Address = "0x0000000000000000000000000000000000000000";

// JSON-RPC Account
const [
  deployerAccount,
  creatorAccount,
  collectorAccount,
  mintFeeRecipientAccount,
] = (await walletClient.getAddresses()) as [Address, Address, Address, Address];

type TestContext = {
  preminterAddress: `0x${string}`;
  forkedChainId: keyof typeof zoraCreator1155FactoryImplAddress;
  anvilChainId: number;
  zoraMintFee: bigint;
  fixedPriceMinterAddress: Address;
};

const deployContractAndGetAddress = async (
  args: Parameters<typeof walletClient.deployContract>[0]
) => {
  const hash = await walletClient.deployContract(args);
  return (
    await publicClient.waitForTransactionReceipt({
      hash,
    })
  ).contractAddress!;
};

export const deployFactoryProxy = async () => {
  console.log("deploying protocol rewards");
  const protocolRewardsAddress = await deployContractAndGetAddress({
    abi: protocolRewards.abi,
    bytecode: protocolRewards.bytecode.object as `0x${string}`,
    account: deployerAccount,
    args: [],
  });

  console.log("deploying attribution lib");
  const attributionAddress = await deployContractAndGetAddress({
    abi: ZoraCreator1155Attribution.abi,
    bytecode: ZoraCreator1155Attribution.bytecode.object as `0x${string}`,
    account: deployerAccount,
  });

  console.log("attribution address is ", attributionAddress);

  console.log("deploying 1155");
  const zora1155Address = await deployContractAndGetAddress({
    abi: zoraCreator1155Impl.abi,
    bytecode: zoraCreator1155Impl.bytecode.object as `0x${string}`,
    account: deployerAccount,
    args: [0n, mintFeeRecipientAccount, zeroAddress, protocolRewardsAddress],
  });

  console.log("deploying fixed priced minter");
  const fixedPriceMinterAddress = await deployContractAndGetAddress({
    abi: zoraCreatorFixedPriceSaleStrategy.abi,
    bytecode: zoraCreatorFixedPriceSaleStrategy.bytecode
      .object as `0x${string}`,
    account: deployerAccount,
  });

  console.log("deploying factory impl");
  const factoryImplAddress = await deployContractAndGetAddress({
    abi: zoraCreator1155FactoryImpl.abi,
    bytecode: zoraCreator1155FactoryImpl.bytecode.object as `0x${string}`,
    account: deployerAccount,
    args: [zora1155Address, zeroAddress, fixedPriceMinterAddress, zeroAddress],
  });

  const factoryProxyAddress = factoryImplAddress!;

  return { factoryProxyAddress, zora1155Address, fixedPriceMinterAddress };
};

export const deployPreminterContract = async () => {
   const factoryProxyAddress = (await deployFactoryProxy()).factoryProxyAddress;

  const deployPreminterHash = await walletClient.deployContract({
    abi: zoraCreator1155PremintExecutor.abi,
    bytecode: zoraCreator1155PremintExecutor.bytecode.object as `0x${string}`,
    account: deployerAccount,
    args: [factoryProxyAddress],
  });

  const receipt = await publicClient.waitForTransactionReceipt({
    hash: deployPreminterHash,
  });

  const preminterAddress = receipt.contractAddress!;

  const initializeHash = await walletClient.writeContract({
    abi: preminterAbi,
    address: preminterAddress,
    functionName: "initialize",
    account: deployerAccount,
    args: [factoryProxyAddress],
  });

  await publicClient.waitForTransactionReceipt({ hash: initializeHash });

  return { preminterAddress, factoryProxyAddress };
};

// create token and contract creation config:
const defaultContractConfig = (): ContractCreationConfig => ({
  contractAdmin: creatorAccount,
  contractURI: "ipfs://asdfasdfasdf",
  contractName: "My fun NFT",
});

const defaultTokenConfig = (
  fixedPriceMinterAddress: Address
): TokenCreationConfig => ({
  tokenURI: "ipfs://tokenIpfsId0",
  maxSupply: 100n,
  maxTokensPerAddress: 10n,
  pricePerToken: parseEther("0.1"),
  mintStart: 0n,
  mintDuration: 100n,
  royaltyMintSchedule: 30,
  royaltyBPS: 200,
  royaltyRecipient: creatorAccount,
  fixedPriceMinter: fixedPriceMinterAddress,
});

const defaultPremintConfig = (fixedPriceMinter: Address): PremintConfig => ({
  tokenConfig: defaultTokenConfig(fixedPriceMinter),
  deleted: false,
  uid: 105,
  version: 0,
});

const useForkContract = true;

describe("ZoraCreator1155Preminter", () => {
  beforeEach<TestContext>(async (ctx) => {
    // deploy signature minter contract
    await testClient.setBalance({
      address: deployerAccount,
      value: parseEther("10"),
    });

    ctx.forkedChainId = zoraTestnet.id;
    ctx.anvilChainId = foundry.id;

    let preminterAddress: Address;

    if (useForkContract) {
      preminterAddress = zoraCreator1155PremintExecutorAddress[ctx.forkedChainId];
    } else {
      const deployed = await deployPreminterContract();
      preminterAddress = deployed.preminterAddress;
    }


    ctx.zoraMintFee = parseEther('0.000777');

    ctx.preminterAddress = preminterAddress;
  }, 20 * 1000);

  it<TestContext>(
    "can sign for another chain",
    async ({ preminterAddress: preminterAddress, fixedPriceMinterAddress }) => {
      const premintConfig = defaultPremintConfig(fixedPriceMinterAddress);
      const contractConfig = defaultContractConfig();

      const contractAddress = await publicClient.readContract({
        abi: preminterAbi,
        address: preminterAddress,
        functionName: "getContractAddress",
        args: [contractConfig],
      });

      const signedMessage = await walletClient.signTypedData({
        ...preminterTypedDataDefinition({
          verifyingContract: contractAddress,
          chainId: 999,
          premintConfig,
        }),
        account: creatorAccount,
      });

      console.log({
        creatorAccount,
        signedMessage,
        premintConfig,
        contractAddress: await publicClient.readContract({
          abi: preminterAbi,
          address: preminterAddress,
          functionName: "getContractAddress",
          args: [defaultContractConfig()],
        }),
      });
    },
    20 * 1000
  );
  it<TestContext>(
    "can sign and recover a signature",
    async ({
      preminterAddress: preminterAddress,
      anvilChainId,
      fixedPriceMinterAddress,
    }) => {
      const premintConfig = defaultPremintConfig(fixedPriceMinterAddress);
      const contractConfig = defaultContractConfig();

      const contractAddress = await publicClient.readContract({
        abi: preminterAbi,
        address: preminterAddress,
        functionName: "getContractAddress",
        args: [contractConfig],
      });

      // sign message containing contract and token creation config and uid
      const signedMessage = await walletClient.signTypedData({
        ...preminterTypedDataDefinition({
          verifyingContract: contractAddress,
          // we need to sign here for the anvil chain, cause thats where it is run on
          chainId: anvilChainId,
          premintConfig,
        }),
        account: creatorAccount,
      });

      // recover and verify address is correct
      const recoveredAddress = await publicClient.readContract({
        abi: preminterAbi,
        address: preminterAddress,
        functionName: "recoverSigner",
        args: [
          premintConfig,
          contractAddress,
          signedMessage,
          BigInt(anvilChainId),
        ],
      });

      expect(recoveredAddress).to.equal(creatorAccount);
    },

    20 * 1000
  );

  it<TestContext>(
    "can sign and mint multiple tokens",
    async ({
      zoraMintFee,
      anvilChainId,
      preminterAddress: preminterAddress,
      fixedPriceMinterAddress,
    }) => {
      // setup contract and token creation parameters
      const premintConfig = defaultPremintConfig(fixedPriceMinterAddress);
      const contractConfig = defaultContractConfig();

      // lets make it a random number to not break the existing tests that expect fresh data
      premintConfig.uid = Math.round(Math.random() * 1000000);

      let contractAddress = await publicClient.readContract({
        abi: preminterAbi,
        address: preminterAddress,
        functionName: "getContractAddress",
        args: [contractConfig],
      });

      // have creator sign the message to create the contract
      // and the token
      const signedMessage = await walletClient.signTypedData({
        ...preminterTypedDataDefinition({
          verifyingContract: preminterAddress,
          chainId: anvilChainId,
          premintConfig,
        }),
        // signer account is the creator
        account: creatorAccount,
      });

      const quantityToMint = 2n;

      const valueToSend =
        (zoraMintFee + premintConfig.tokenConfig.pricePerToken) *
        quantityToMint;

      const comment = "I love this!";

      await testClient.setBalance({
        address: collectorAccount,
        value: 10n * 10n ** 18n,
      });

      // get the premint status - it should not be minted
      let tokenId = await publicClient.readContract({
        abi: zoraCreator1155ImplABI,
        address: contractAddress,
        functionName: "delegatedTokenId",
        args: [premintConfig.uid],
      });

      expect(tokenId).toBe(0n);
      // expect(contractAddress).toBe(zeroAddress);

      // now have the collector execute the first signed message;
      // it should create the contract, the token,
      // and min the quantity to mint tokens to the collector
      // the signature along with contract + token creation
      // parameters are required to call this function
      const mintHash = await walletClient.writeContract({
        abi: preminterAbi,
        functionName: "premint",
        account: collectorAccount,
        address: preminterAddress,
        args: [
          contractConfig,
          premintConfig,
          signedMessage,
          quantityToMint,
          comment,
        ],
        value: valueToSend,
      });

      // ensure it succeeded
      const receipt = await publicClient.waitForTransactionReceipt({
        hash: mintHash,
      });
      // console.log(receipt);
      expect(receipt.status).toBe("success");

      // fetch the premint token id
      let newTokenId = await publicClient.readContract({
        abi: zoraCreator1155ImplABI,
        address: contractAddress,
        functionName: "delegatedTokenId",
        args: [premintConfig.uid],
      });

      expect(newTokenId).not.toBe(0n);

      // now use what was created, to get the balance from the created contract
      const tokenBalance = await publicClient.readContract({
        abi: zoraCreator1155ImplABI,
        address: contractAddress,
        functionName: "balanceOf",
        args: [collectorAccount, newTokenId],
      });

      // get token balance - should be amount that was created
      expect(tokenBalance).toBe(quantityToMint);

      const premintConfig2 = {
        ...premintConfig,
        uid: premintConfig.uid + 1,
        tokenConfig: {
          ...premintConfig.tokenConfig,
          tokenURI: "ipfs://tokenIpfsId2",
          pricePerToken: parseEther("0.05"),
        },
      };

      // sign the message to create the second token
      const signedMessage2 = await walletClient.signTypedData({
        ...preminterTypedDataDefinition({
          verifyingContract: preminterAddress,
          chainId: foundry.id,
          premintConfig: premintConfig2,
        }),
        account: creatorAccount,
      });

      const quantityToMint2 = 4n;

      const valueToSend2 =
        (zoraMintFee + premintConfig2.tokenConfig.pricePerToken) *
        quantityToMint2;

      // now have the collector execute the second signed message.
      // it should create a new token against the existing contract
      const mintHash2 = await walletClient.writeContract({
        abi: preminterAbi,
        functionName: "premint",
        account: collectorAccount,
        address: preminterAddress,
        args: [
          contractConfig,
          premintConfig2,
          signedMessage2,
          quantityToMint2,
          comment,
        ],
        value: valueToSend2,
      });

      expect(
        (await publicClient.waitForTransactionReceipt({ hash: mintHash2 }))
          .status
      ).toBe("success");

      // now premint status for the second mint, it should be minted
      tokenId = await publicClient.readContract({
        abi: zoraCreator1155ImplABI,
        address: contractAddress,
        functionName: "delegatedTokenId",
        args: [premintConfig2.uid],
      });

      expect(tokenId).not.toBe(0n);

      // get balance of second token
      const tokenBalance2 = await publicClient.readContract({
        abi: zoraCreator1155ImplABI,
        address: contractAddress,
        functionName: "balanceOf",
        args: [collectorAccount, tokenId],
      });

      expect(tokenBalance2).toBe(quantityToMint2);
    },
    // 10 second timeout
    40 * 1000
  );
});
