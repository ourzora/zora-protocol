import { createTestClient, http, createWalletClient, createPublicClient, } from 'viem'
import { foundry, mainnet } from 'viem/chains'
import { describe, it, beforeEach, beforeAll } from 'vitest';
import { parseEther } from 'viem'
import { zoraCreator1155FactoryImplConfig, zoraCreator1155PreminterABI as preminterAbi } from '../package/wagmiGenerated';
import { ExtractAbiFunction, AbiParametersToPrimitiveTypes} from 'abitype';
import preminter from '../out/ZoraCreator1155Preminter.sol/ZoraCreator1155Preminter.json';

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
const [deployerAccount, creatorAccount, collectorAccount] = await walletClient.getAddresses()

type TestContext = {
  preminterAddress: `0x${string}`
};


const deployPreminterContract = async () => {
  const factoryProxyAddress = zoraCreator1155FactoryImplConfig.address[mainnet.id].toLowerCase() as `0x${string}`;

  const fixedPriceMinterAddress = await publicClient.readContract({
    abi: zoraCreator1155FactoryImplConfig.abi,
    address: factoryProxyAddress,
    functionName: 'fixedPriceMinter',
  })

  console.log('deploying preminter contract');
  const deployPreminterHash = await walletClient.deployContract({
    abi: preminter.abi,
    bytecode: preminter.bytecode.object as `0x${string}`,
    account: deployerAccount,
  })

  const receipt = await publicClient.waitForTransactionReceipt({ hash: deployPreminterHash })

  const contractAddress = receipt.contractAddress!;

  console.log('initializing preminter contract');
  const initializeHash = await walletClient.writeContract({
    abi: preminterAbi,
    address: contractAddress,
    functionName: 'initialize',
    account: deployerAccount,
    args: [factoryProxyAddress, fixedPriceMinterAddress]
  })

  await publicClient.waitForTransactionReceipt({ hash: initializeHash })

  return {
    contractAddress
  }
}

type PreminterHashDataTypes = AbiParametersToPrimitiveTypes<
  ExtractAbiFunction<typeof preminterAbi, 'premintHashData'>['inputs']
>;

type ContractCreationConfig = PreminterHashDataTypes[0];
type TokenCreationConfig = PreminterHashDataTypes[1];


describe("ZoraCreator1155Preminter", () => {
  beforeEach<TestContext>(async (ctx) => {
    // deploy signature minter contract
    await testClient.setBalance({
      address: deployerAccount,
      value: parseEther('10') 
    })

    const {contractAddress} = await deployPreminterContract();

    ctx.preminterAddress = contractAddress;

  });

  it<TestContext>("can sign and execute a signature", async ({preminterAddress}) => {
    const contractConfig: ContractCreationConfig = {
      contractAdmin: creatorAccount,
      contractName: 'My fun NFT',
      contractURI: 'ipfs://asdfasdfasdf',
      defaultRoyaltyConfiguration: {
        royaltyBPS: 200,
        royaltyRecipient: creatorAccount,
        royaltyMintSchedule: 30
      }
    };

    const tokenConfig: TokenCreationConfig = {
      tokenMaxSupply: 100n,
      tokenURI: 'ipfs://tokenIpfsId0',
      tokenSalesConfig: {
        duration: 100n,
        maxTokensPerAddress: 10n,
        pricePerToken: parseEther('0.1'),
      }
    }
  
    const chainId = mainnet.id;
  
    const digest = await publicClient.readContract({
      abi: preminterAbi,
      address: preminterAddress,
      functionName: 'premintHashData',
      args: [contractConfig, tokenConfig, chainId]
    });

    const signedMessage = await walletClient.signeMessage({
      account: creatorAccount,
      message: { raw: digest }
    })


    // now execute the signature
    const executeHash = await walletClient.writeContract({
      abi: preminterAbi,
      address: preminterAddress,
    });
  });
})


