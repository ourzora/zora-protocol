import { createTestClient, http, createWalletClient, createPublicClient, custom } from 'viem'
import { foundry } from 'viem/chains'
import { describe, it, beforeEach } from 'vitest';
import { parseEther } from 'viem'
import { zoraCreator1155FactoryImplABI, zoraCreator1155FactoryImplConfig } from '../package/wagmiGenerated';
import zoraStrategy from '../out/ZoraCreatorSignatureMinterStrategy.sol/ZoraCreatorSignatureMinterStrategy.json';

const walletClient = createWalletClient({
  chain: foundry,
  transport: http(), 
})

export const walletClientWithAccount = createWalletClient({
  chain: foundry,
  transport: http(),
})

const testClient = createTestClient({
  chain: foundry,
  mode: 'anvil',
  transport: http(), 
})

const publicClient = createPublicClient({
  chain: foundry,
  transport: http()
})

// JSON-RPC Account
const [creatorAccount, adminAccount, royaltyRecipient] = await walletClient.getAddresses()

type TestContext = {
  signatureMinterAddress: `0x${string}`
};


describe("ZoraCreatorSignatureMinterStrategy", () => {
  beforeEach<TestContext>(async (ctx) => {
    // deploy signature minter contract
    await testClient.setBalance({
      address: creatorAccount,
      value: parseEther('10') 
    })

    const hash = await walletClient.deployContract({
      abi: zoraStrategy.abi,
      bytecode: zoraStrategy.bytecode.object as `0x${string}`,
      account: creatorAccount,
    })

    const receipt = await publicClient.waitForTransactionReceipt({ hash })

    const contractAddress = receipt.contractAddress!;

    ctx.signatureMinterAddress = contractAddress;
  });

  it<TestContext>("can be setup with the setup actions", async ({signatureMinterAddress}) => {
    const contractUri = 'asdfasfdas';
    const contractName = 'blah';
  
    const royaltyConfiguration: { royaltyMintSchedule: number; royaltyBPS: number; royaltyRecipient: `0x${string}`; } = {
      royaltyMintSchedule: 0,
      royaltyBPS: 0,
      royaltyRecipient
    };
  
    const x = await publicClient.simulateContract({
      abi: zoraCreator1155FactoryImplABI,
      account: creatorAccount,
      functionName: 'createContract',
      address: zoraCreator1155FactoryImplConfig.address[1],
      args: [
        contractUri,
        contractName,
        royaltyConfiguration,
        adminAccount,
        []
      ]
    })
  });
})


