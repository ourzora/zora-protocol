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
  zoraCreatorSignatureMinterStrategyABI as signatureMinterAbi,
} from "./wagmiGenerated";
import { chainConfigs } from "./chainConfigs";
import signatureMinter from "../out/ZoraCreatorSignatureMinterStrategy.sol/ZoraCreatorSignatureMinterStrategy.json";
import {
  SignatureMinterHashTypeDataConfig,
  signatureMinterTypedDataDefinition,
} from "./signatureMinter";

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
  signatureMinterAddress: `0x${string}`;
  forkedChainId: keyof typeof zoraCreator1155FactoryImplConfig.address;
  anvilChainId: number;
  zoraMintFee: bigint;
};

export const deploySignatureMinterContract = async () => {
  const deploySignatureMinterHash = await walletClient.deployContract({
    abi: signatureMinter.abi,
    bytecode: signatureMinter.bytecode.object as `0x${string}`,
    account: deployerAccount,
  });

  const receipt = await publicClient.waitForTransactionReceipt({
    hash: deploySignatureMinterHash,
  });

  const contractAddress = receipt.contractAddress!;

  return contractAddress;
};

describe("ZoraCreator1155Preminter", () => {
  beforeEach<TestContext>(async (ctx) => {
    await testClient.setBalance({
      address: deployerAccount,
      value: parseEther("10"),
    });

    ctx.forkedChainId = zoraTestnet.id;
    ctx.anvilChainId = foundry.id;
    ctx.signatureMinterAddress = await deploySignatureMinterContract();
    ctx.zoraMintFee = BigInt(chainConfigs[ctx.forkedChainId].MINT_FEE_AMOUNT);
  });

  it<TestContext>("can sign and recover a signature", async ({
    signatureMinterAddress,
    anvilChainId,
  }) => {
    const signatureMinterConfig: SignatureMinterHashTypeDataConfig = [
      "0x0000000000000000000000000000000000000000",
      1n,
      "0x6173646661736466000000000000000000000000000000000000000000000000",
      1n,
      1n,
      0n,
      collectorAccount,
      creatorAccount,
    ];

    const signedMessage = await walletClient.signTypedData({
      ...signatureMinterTypedDataDefinition({
        verifyingContract: signatureMinterAddress,
        chainId: anvilChainId,
        signatureMinterConfig,
      }),
      account: collectorAccount,
    });

    const recoveredAddress = await publicClient.readContract({
      abi: signatureMinterAbi,
      address: signatureMinterAddress,
      functionName: "recoverSignature",
      args: [...signatureMinterConfig, signedMessage],
    });

    expect(recoveredAddress).to.equal(collectorAccount);
  });
});
