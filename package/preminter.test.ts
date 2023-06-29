import {
  createTestClient,
  http,
  createWalletClient,
  createPublicClient,
} from "viem";
import { zoraTestnet, foundry } from "viem/chains";
import { describe, it, beforeEach, expect } from "vitest";
import { parseEther } from "viem";
import {
  zoraCreator1155FactoryImplConfig,
  zoraCreator1155PreminterABI as preminterAbi,
  zoraCreator1155ImplABI,
  zoraCreator1155PreminterAddress,
} from "./wagmiGenerated";
import { chainConfigs } from "./chainConfigs";
import preminter from "../out/ZoraCreator1155Preminter.sol/ZoraCreator1155Preminter.json";
import {
  ContractCreationConfig,
  PremintConfig,
  TokenCreationConfig,
  preminterTypedDataDefinition,
} from "./preminter";

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

const zeroAddress: Address = '0x0000000000000000000000000000000000000000';

// JSON-RPC Account
const [deployerAccount, creatorAccount, collectorAccount] =
  (await walletClient.getAddresses()) as [Address, Address, Address];

type TestContext = {
  forkedPreminterAddress: `0x${string}`;
  forkedChainId: keyof typeof zoraCreator1155PreminterAddress;
  anvilChainId: number;
  zoraMintFee: bigint;
};

export const deployPreminterContract = async (
  forkChainId: keyof typeof zoraCreator1155FactoryImplConfig.address
) => {
  // hardcode to zora fork
  const factoryProxyAddress = zoraCreator1155FactoryImplConfig.address[
    forkChainId
  ].toLowerCase() as `0x${string}`;

  const deployPreminterHash = await walletClient.deployContract({
    abi: preminter.abi,
    bytecode: preminter.bytecode.object as `0x${string}`,
    account: deployerAccount,
  });

  const receipt = await publicClient.waitForTransactionReceipt({
    hash: deployPreminterHash,
  });

  const contractAddress = receipt.contractAddress!;

  const initializeHash = await walletClient.writeContract({
    abi: preminterAbi,
    address: contractAddress,
    functionName: "initialize",
    account: deployerAccount,
    args: [factoryProxyAddress],
  });

  await publicClient.waitForTransactionReceipt({ hash: initializeHash });

  return contractAddress;
};

// create token and contract creation config:
const defaultContractConfig = (): ContractCreationConfig => ({
  contractAdmin: creatorAccount,
  contractURI: "ipfs://asdfasdfasdf",
  contractName: "My fun NFT",
});

const defaultTokenConfig = (): TokenCreationConfig => ({
  tokenURI: "ipfs://tokenIpfsId0",
  maxSupply: 100n,
  maxTokensPerAddress: 10n,
  pricePerToken: parseEther("0.1"),
  mintStart: 0n,
  mintDuration: 100n,
  royaltyMintSchedule: 30,
  royaltyBPS: 200,
  royaltyRecipient: creatorAccount,
});

const defaultPremintConfig = (): PremintConfig => ({
  contractConfig: defaultContractConfig(),
  tokenConfig: defaultTokenConfig(),
  deleted: false,
  uid: 105,
  version: 0,
});

describe("ZoraCreator1155Preminter", () => {
  beforeEach<TestContext>(async (ctx) => {
    // deploy signature minter contract
    await testClient.setBalance({
      address: deployerAccount,
      value: parseEther("10"),
    });

    ctx.forkedChainId = zoraTestnet.id;
    ctx.anvilChainId = foundry.id;

    ctx.forkedPreminterAddress =
      zoraCreator1155PreminterAddress[ctx.forkedChainId];
    ctx.forkedPreminterAddress = await deployPreminterContract(ctx.forkedChainId);
    ctx.zoraMintFee = BigInt(chainConfigs[ctx.forkedChainId].MINT_FEE_AMOUNT);
  });

  it<TestContext>("can sign for another chain", async ({
    forkedPreminterAddress: preminterAddress,
  }) => {
    const premintConfig = defaultPremintConfig();

    const signedMessage = await walletClient.signTypedData({
      ...preminterTypedDataDefinition({
        verifyingContract: preminterAddress,
        chainId: 999,
        premintConfig,
      }),
      account: creatorAccount,
    });

    console.log({
      creatorAccount,
      signedMessage,
      premintConfig,
      contractHashId: await publicClient.readContract({
        abi: preminterAbi,
        address: preminterAddress,
        functionName: "contractDataHash",
        args: [defaultContractConfig()],
      }),
    });
  });
  it<TestContext>("can sign and recover a signature", async ({
    forkedPreminterAddress: preminterAddress,
    anvilChainId,
  }) => {
    const premintConfig = defaultPremintConfig();

    console.log({
      defaultMind: defaultPremintConfig()
    })

    // sign message containing contract and token creation config and uid
    const signedMessage = await walletClient.signTypedData({
      ...preminterTypedDataDefinition({
        verifyingContract: preminterAddress,
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
      args: [premintConfig, signedMessage],
    });

    expect(recoveredAddress).to.equal(creatorAccount);
  });

  it<TestContext>(
    "can sign and mint multiple tokens",
    async ({ zoraMintFee, anvilChainId, forkedChainId }) => {
      // setup contract and token creation parameters
      const premintConfig = defaultPremintConfig();

      const preminterAddress = await deployPreminterContract(forkedChainId);

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
      let [minted, contractAddress, tokenId]= await publicClient.readContract({
        abi: preminterAbi,
        address: preminterAddress,
        functionName: 'premintStatus',
        args: [premintConfig.contractConfig, premintConfig.uid]
      })

      expect(minted).toBe(false);
      expect(contractAddress).toBe(zeroAddress);

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
        args: [premintConfig, signedMessage, quantityToMint, comment],
        value: valueToSend,
      });

      // ensure it succeeded
      expect(
        (await publicClient.waitForTransactionReceipt({ hash: mintHash }))
          .status
      ).toBe("success");

      // fetch the status, it should show that it's minted
      [minted, contractAddress, tokenId] = await publicClient.readContract({
        abi: preminterAbi,
        address: preminterAddress,
        functionName: 'premintStatus',
        args: [premintConfig.contractConfig, premintConfig.uid]
      })

      expect(minted).toBe(true);
      expect(contractAddress).not.toBe(zeroAddress);
      expect(tokenId).not.toBe(0n);

      // now use what was created, to get the balance from the created contract
      const tokenBalance = await publicClient.readContract({
        abi: zoraCreator1155ImplABI,
        address: contractAddress,
        functionName: "balanceOf",
        args: [collectorAccount, tokenId],
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
        args: [premintConfig2, signedMessage2, quantityToMint2, comment],
        value: valueToSend2,
      });

      expect(
        (await publicClient.waitForTransactionReceipt({ hash: mintHash2 }))
          .status
      ).toBe("success");

      // now premint status for the second mint, it should be minted
      [minted, contractAddress, tokenId] = await publicClient.readContract({
        abi: preminterAbi,
        address: preminterAddress,
        functionName: 'premintStatus',
        args: [premintConfig2.contractConfig, premintConfig2.uid]
      })

      expect(minted).toBe(true);

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
    20 * 1000
  );
});
