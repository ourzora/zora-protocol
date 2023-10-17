import {
  createTestClient,
  http,
  createWalletClient,
  createPublicClient,
} from "viem";
import { foundry, zoraTestnet } from "viem/chains";
import { describe, it, beforeEach, expect, vi } from "vitest";
import { parseEther } from "viem";
import {
  zoraCreator1155PremintExecutorImplABI as preminterAbi,
  zoraCreator1155PremintExecutorImplAddress as zoraCreator1155PremintExecutorAddress,
  zoraCreator1155ImplABI,
  zoraCreator1155FactoryImplAddress,
  zoraCreator1155FactoryImplConfig,
} from "./wagmiGenerated";
import ZoraCreator1155Attribution from "../out/ZoraCreator1155Attribution.sol/ZoraCreator1155Attribution.json";
import zoraCreator1155PremintExecutor from "../out/ZoraCreator1155PremintExecutorImpl.sol/ZoraCreator1155PremintExecutorImpl.json";
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
import { PreminterAPI } from "./premint-api";

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
const [deployerAccount, creatorAccount, collectorAccount] =
  (await walletClient.getAddresses()) as [Address, Address, Address, Address];

type TestContext = {
  preminterAddress: `0x${string}`;
  forkedChainId: keyof typeof zoraCreator1155FactoryImplAddress;
  anvilChainId: number;
  zoraMintFee: bigint;
  fixedPriceMinterAddress: Address;
};

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

    const factoryProxyAddress =
      zoraCreator1155FactoryImplAddress[ctx.forkedChainId];
    // ctx.fixedPriceMinterAddress = await publicClient.readContract({
    //   abi: zoraCreator1155FactoryImplConfig.abi,
    //   address: zoraCreator1155FactoryImplAddress[ctx.forkedChainId],
    //   functionName: "fixedPriceMinter",
    // });
    preminterAddress = zoraCreator1155PremintExecutorAddress[ctx.forkedChainId];

    ctx.zoraMintFee = parseEther("0.000777");

    ctx.preminterAddress = preminterAddress;
  }, 20 * 1000);

  // skip for now - we need to make this work on zora testnet chain too
  it<TestContext>(
    "can sign on the forked premint contract",
    async ({ fixedPriceMinterAddress, forkedChainId, anvilChainId }) => {
      const preminterApi = new PreminterAPI(foundry);
      
      (zoraTestnet as any).id = anvilChainId;

      preminterApi.get = vi.fn().mockResolvedValue({ next_uid: 3 });
      preminterApi.post = vi.fn().mockResolvedValue({ ok: true });

      const premint = await preminterApi.createPremint({
        walletClient,
        publicClient,
        account: deployerAccount,
        checkSignature: true,
        collection: {
          contractAdmin: deployerAccount,
          contractName: "Testing Contract",
          contractURI: "https://zora.co/testing/contract.json",
        },
        mint: {
          tokenURI: "https://zora.co/testing/token.json",
        },
      });

      expect(preminterApi.post).toHaveBeenCalledWith(
        "https://api.zora.co/premint/signature",
        {
          chain_name: "ZORA-TESTNET",
          collection: {
            contractAdmin: "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
            contractName: "Testing Contract",
            contractURI: "https://zora.co/testing/contract.json",
          },
          premint: {
            deleted: false,
            tokenConfig: {
              fixedPriceMinter: "0x04E2516A2c207E84a1839755675dfd8eF6302F0a",
              maxSupply: "18446744073709551615",
              maxTokensPerAddress: "0",
              mintDuration: "604800",
              mintStart: "0",
              pricePerToken: "18446744073709551615",
              royaltyBPS: 1000,
              royaltyMintSchedule: 0,
              royaltyRecipient: "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
              tokenURI: "https://zora.co/testing/token.json",
            },
            uid: 3,
            version: 1,
          },
          signature:
            "0x1560c8bd247c7432c1e53049fd0ccb1287df6e7cad4649718417ed7f08db45c87f6ba03aafb61dcbfbbd66fafddaa63bbe303bb9bcd7abd30ebc49becda5952f1c",
        }
      );

      console.log({ premint });
    },
    20 * 1000
  );

  it<TestContext>(
    "can execute premint on network",
    async ({ fixedPriceMinterAddress, forkedChainId, anvilChainId }) => {
      const preminterApi = new PreminterAPI(foundry);

      preminterApi.get = vi.fn().mockResolvedValue({
        chain_name: "ZORA-TESTNET",
        collection: {
          contractAdmin: "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
          contractName: "Testing Contract",
          contractURI: "https://zora.co/testing/contract.json",
        },
        premint: {
          deleted: false,
          tokenConfig: {
            fixedPriceMinter: "0x04E2516A2c207E84a1839755675dfd8eF6302F0a",
            maxSupply: "18446744073709551615",
            maxTokensPerAddress: "0",
            mintDuration: "604800",
            mintStart: "0",
            pricePerToken: "18446744073709551615",
            royaltyBPS: 1000,
            royaltyMintSchedule: 0,
            royaltyRecipient: "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
            tokenURI: "https://zora.co/testing/token.json",
          },
          uid: 3,
          version: 1,
        },
        signature:
          "0x1560c8bd247c7432c1e53049fd0ccb1287df6e7cad4649718417ed7f08db45c87f6ba03aafb61dcbfbbd66fafddaa63bbe303bb9bcd7abd30ebc49becda5952f1c",
      });
      preminterApi.post = vi.fn();

      console.log({deployerAccount})

      const premint = await preminterApi.executePremintWithWallet({
        data: await preminterApi.getPremintData('0x0bdD2Fcb03912403c0B4699EDBB6bDAd65dACf62', 3),
        account: deployerAccount,
        walletClient,
        publicClient,
        mintArguments: {
          quantityToMint: 1n,
          mintComment: '',
        },
      });

      console.log({ premint });
    },
    20 * 1000
  );
});
