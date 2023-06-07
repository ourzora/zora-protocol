import {
  createTestClient,
  http,
  createWalletClient,
  createPublicClient,
} from "viem";
import { foundry, mainnet } from "viem/chains";
import { describe, it, beforeEach, expect } from "vitest";
import { parseEther } from "viem";
import {
  zoraCreator1155FactoryImplConfig,
  zoraCreator1155PreminterABI as preminterAbi,
  zoraCreator1155ImplABI,
} from "./wagmiGenerated";
import { chainConfigs } from "./chainConfigs";
import preminter from "../out/ZoraCreator1155Preminter.sol/ZoraCreator1155Preminter.json";
import { ContractCreationConfig, TokenCreationConfig, preminterTypedDataDefinition } from "./preminter";

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

// JSON-RPC Account
const [deployerAccount, creatorAccount, collectorAccount] =
  (await walletClient.getAddresses()) as [Address, Address, Address];

type TestContext = {
  preminterAddress: `0x${string}`;
  zoraMintFee: bigint;
};

const deployPreminterContract = async () => {
  const factoryProxyAddress = zoraCreator1155FactoryImplConfig.address[
    mainnet.id
  ].toLowerCase() as `0x${string}`;

  const fixedPriceMinterAddress = await publicClient.readContract({
    abi: zoraCreator1155FactoryImplConfig.abi,
    address: factoryProxyAddress,
    functionName: "fixedPriceMinter",
  });

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
    args: [factoryProxyAddress, fixedPriceMinterAddress],
  });

  await publicClient.waitForTransactionReceipt({ hash: initializeHash });

  return {
    contractAddress,
  };
};

describe("ZoraCreator1155Preminter", () => {
  beforeEach<TestContext>(async (ctx) => {
    // deploy signature minter contract
    await testClient.setBalance({
      address: deployerAccount,
      value: parseEther("10"),
    });

    const { contractAddress } = await deployPreminterContract();

    ctx.preminterAddress = contractAddress;
    ctx.zoraMintFee = BigInt(chainConfigs[mainnet.id].MINT_FEE_AMOUNT);
  });

  it<TestContext>("can sign and recover a signature", async ({
    preminterAddress,
  }) => {
    const contractConfig: ContractCreationConfig = {
      contractAdmin: creatorAccount,
      contractURI: "ipfs://asdfasdfasdf",
      contractName: "My fun NFT",
      royaltyMintSchedule: 30,
      royaltyBPS: 200,
      royaltyRecipient: creatorAccount,
    };

    const tokenConfig: TokenCreationConfig = {
      tokenURI: "ipfs://tokenIpfsId0",
      maxSupply: 100n,
      maxTokensPerAddress: 10n,
      pricePerToken: parseEther("0.1"),
      saleDuration: 100n,
    };

    const signedMessage = await walletClient.signTypedData({
      ...preminterTypedDataDefinition({
        preminterAddress,
        chainId: foundry.id,
        contractConfig,
        tokenConfig,
      }),
      account: creatorAccount,
    });

    const recoveredAddress = await publicClient.readContract({
      abi: preminterAbi,
      address: preminterAddress,
      functionName: "recoverSigner",
      args: [contractConfig, tokenConfig, signedMessage],
    });

    expect(recoveredAddress).to.equal(creatorAccount);
  });

  it<TestContext>("can sign and mint multiple tokens", async ({
    preminterAddress,
    zoraMintFee,
  }) => {
    const contractConfig: ContractCreationConfig = {
      contractAdmin: creatorAccount,
      contractURI: "ipfs://asdfasdfasdf",
      contractName: "My fun NFT",
      royaltyMintSchedule: 30,
      royaltyBPS: 200,
      royaltyRecipient: creatorAccount,
    };

    const tokenConfig: TokenCreationConfig = {
      tokenURI: "ipfs://tokenIpfsId0",
      maxSupply: 100n,
      maxTokensPerAddress: 10n,
      pricePerToken: parseEther("0.1"),
      saleDuration: 100n,
    };

    const signedMessage = await walletClient.signTypedData({
      ...preminterTypedDataDefinition({
        preminterAddress,
        chainId: foundry.id,
        contractConfig,
        tokenConfig,
      }),
      account: creatorAccount,
    });

    const quantityToMint = 2n;

    const valueToSend = (zoraMintFee + tokenConfig.pricePerToken) * quantityToMint;

    // now have the collector execute the first signed message
    const mintHash = await walletClient.writeContract({
      abi: preminterAbi,
      functionName: 'premint',
      account: collectorAccount,
      address: preminterAddress,
      args: [contractConfig, tokenConfig, quantityToMint, signedMessage],
      value: valueToSend
    })

    const receipt = await publicClient.waitForTransactionReceipt({ hash: mintHash });

    expect(receipt.status).toBe('success');

    const contractHash = await publicClient.readContract({
      abi: preminterAbi,
      address: preminterAddress,
      functionName: 'contractDataHash',
      args: [contractConfig]
    });

    const mintedContractAddress = await publicClient.readContract({
      abi: preminterAbi,
      address: preminterAddress,
      functionName: 'contractAddresses',
      args: [contractHash]
    });

    const tokenBalance = await publicClient.readContract({
      abi: zoraCreator1155ImplABI,
      address: mintedContractAddress,
      functionName: 'balanceOf',
      args: [collectorAccount, 1n]
    })

    expect(tokenBalance).toBe(quantityToMint);
  });
});
