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
} from "./wagmiGenerated";
import { chainConfigs } from "./chainConfigs";
import { ExtractAbiFunction, AbiParametersToPrimitiveTypes } from "abitype";
import preminter from "../out/ZoraCreator1155Preminter.sol/ZoraCreator1155Preminter.json";

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

type PreminterHashInputs = ExtractAbiFunction<
  typeof preminterAbi,
  "premintHashData"
>["inputs"];

type PreminterHashDataTypes =
  AbiParametersToPrimitiveTypes<PreminterHashInputs>;

type ContractCreationConfig = PreminterHashDataTypes[0];
type TokenCreationConfig = PreminterHashDataTypes[1];

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
      domain: {
        chainId: foundry.id,
        name: "Preminter",
        version: "0.0.1",
        verifyingContract: preminterAddress,
      },
      types: {
        ContractAndToken: [
          { name: "contractConfig", type: "ContractCreationConfig" },
          { name: "tokenConfig", type: "TokenCreationConfig" },
        ],
        ContractCreationConfig: [
          { name: "contractAdmin", type: "address" },
          { name: "contractURI", type: "string" },
          { name: "contractName", type: "string" },
          { name: "royaltyMintSchedule", type: "uint32" },
          { name: "royaltyBPS", type: "uint32" },
          { name: "royaltyRecipient", type: "address" },
        ],
        TokenCreationConfig: [
          { name: "tokenURI", type: "string" },
          { name: "maxSupply", type: "uint256" },
          { name: "maxTokensPerAddress", type: "uint64" },
          { name: "pricePerToken", type: "uint96" },
          { name: "saleDuration", type: "uint64" },
        ],
      },
      account: creatorAccount,
      message: {
        contractConfig,
        tokenConfig,
      },
      primaryType: "ContractAndToken",
    });

    const recoveredAddress = await publicClient.readContract({
      abi: preminterAbi,
      address: preminterAddress,
      functionName: "recoverSigner",
      args: [contractConfig, tokenConfig, signedMessage],
    });

    expect(recoveredAddress).to.equal(creatorAccount);
  });
});
