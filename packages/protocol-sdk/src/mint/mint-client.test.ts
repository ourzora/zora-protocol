import { describe, expect } from "vitest";
import { Address, erc20Abi, parseAbi, parseEther } from "viem";
import { zora } from "viem/chains";
import {
  zoraCreator1155ImplABI,
  erc20MinterAddress as erc20MinterAddresses,
} from "@zoralabs/protocol-deployments";
import { anvilTest, forkUrls, makeAnvilTest } from "src/anvil";
import { createCollectorClient } from "src/sdk";
import { requestErc20ApprovalForMint } from "./mint-client";

const erc721ABI = parseAbi([
  "function balanceOf(address owner) public view returns (uint256)",
] as const);

describe("mint-helper", () => {
  anvilTest(
    "mints a new 1155 token",
    async ({ viemClients }) => {
      const { testClient, walletClient, publicClient } = viemClients;
      const creatorAccount = (await walletClient.getAddresses())[0]!;
      await testClient.setBalance({
        address: creatorAccount,
        value: parseEther("2000"),
      });
      const targetContract: Address =
        "0xa2fea3537915dc6c7c7a97a82d1236041e6feb2e";
      const targetTokenId = 1n;
      const collectorClient = createCollectorClient({
        chainId: zora.id,
        publicClient,
      });

      const params = await collectorClient.mint({
        minterAccount: creatorAccount,
        tokenId: targetTokenId,
        tokenContract: targetContract,
        mintType: "1155",
        mintRecipient: creatorAccount,
        quantityToMint: 1,
      });

      const oldBalance = await publicClient.readContract({
        abi: zoraCreator1155ImplABI,
        address: targetContract,
        functionName: "balanceOf",
        args: [creatorAccount, targetTokenId],
      });

      const simulationResult = await publicClient.simulateContract(params);

      const hash = await walletClient.writeContract(simulationResult.request);
      const receipt = await publicClient.waitForTransactionReceipt({ hash });
      const newBalance = await publicClient.readContract({
        abi: zoraCreator1155ImplABI,
        address: targetContract,
        functionName: "balanceOf",
        args: [creatorAccount, targetTokenId],
      });
      expect(receipt).to.not.be.null;
      expect(oldBalance).to.be.equal(0n);
      expect(newBalance).to.be.equal(1n);
    },
    12 * 1000,
  );

  makeAnvilTest({
    forkUrl: forkUrls.zoraMainnet,
    forkBlockNumber: 6133407,
    anvilChainId: zora.id,
  })(
    "mints a new 721 token",
    async ({ viemClients }) => {
      const { testClient, walletClient, publicClient } = viemClients;
      const creatorAccount = (await walletClient.getAddresses())[0]!;
      await testClient.setBalance({
        address: creatorAccount,
        value: parseEther("2000"),
      });

      const targetContract: Address =
        "0x7aae7e67515A2CbB8585C707Ca6db37BDd3EA839";
      const collectorClient = createCollectorClient({
        chainId: zora.id,
        publicClient,
      });

      const params = await collectorClient.mint({
        tokenContract: targetContract,
        minterAccount: creatorAccount,
        mintRecipient: creatorAccount,
        quantityToMint: 1,
        mintType: "721",
      });
      const oldBalance = await publicClient.readContract({
        abi: erc721ABI,
        address: targetContract,
        functionName: "balanceOf",
        args: [creatorAccount],
      });

      const simulated = await publicClient.simulateContract(params);

      const hash = await walletClient.writeContract(simulated.request);

      const receipt = await publicClient.waitForTransactionReceipt({ hash });
      expect(receipt).not.to.be.null;

      const newBalance = await publicClient.readContract({
        abi: erc721ABI,
        address: targetContract,
        functionName: "balanceOf",
        args: [creatorAccount],
      });

      expect(oldBalance).to.be.equal(0n);
      expect(newBalance).to.be.equal(1n);
    },
    12 * 1000,
  );

  makeAnvilTest({
    forkUrl: forkUrls.zoraMainnet,
    forkBlockNumber: 14484183,
    anvilChainId: zora.id,
  })(
    "mints an 1155 token with an ERC20 token",
    async ({ viemClients }) => {
      const { testClient, walletClient, publicClient, chain } = viemClients;

      const targetContract: Address =
        "0x689bc305456c38656856d12469aed282fbd89fe0";
      const targetTokenId = 16n;

      const minter = createCollectorClient({ chainId: chain.id, publicClient });

      const mockCollector = "0xb6b701878a1f80197dF2c209D0BDd292EA73164D";
      await testClient.impersonateAccount({
        address: mockCollector,
      });

      const erc20Currency = "0xa6b280b42cb0b7c4a4f789ec6ccc3a7609a1bc39";
      const erc20PricePerToken = 1000000000000000000n;

      const beforeERC20Balance = await publicClient.readContract({
        abi: erc20Abi,
        address: erc20Currency,
        functionName: "balanceOf",
        args: [mockCollector],
      });

      const quantityToMint = 3n;

      const quantityErc20 = erc20PricePerToken * BigInt(quantityToMint);

      const { request } = await publicClient.simulateContract(
        requestErc20ApprovalForMint({
          erc20MinterAddress:
            erc20MinterAddresses[chain.id as keyof typeof erc20MinterAddresses],
          tokenAddress: erc20Currency,
          account: mockCollector,
          quantityErc20,
        }),
      );
      const approveHash = await walletClient.writeContract(request);
      const approveTxReciept = await publicClient.waitForTransactionReceipt({
        hash: approveHash,
      });
      expect(approveTxReciept).to.not.be.null;

      const params = await minter.mint({
        minterAccount: mockCollector,
        tokenId: targetTokenId,
        tokenContract: targetContract,
        mintRecipient: mockCollector,
        quantityToMint,
        mintType: "1155",
      });

      const beforeCollector1155Balance = await publicClient.readContract({
        abi: zoraCreator1155ImplABI,
        address: targetContract,
        functionName: "balanceOf",
        args: [mockCollector, targetTokenId],
      });
      expect(beforeCollector1155Balance).to.be.equal(0n);

      const simulationResult = await publicClient.simulateContract(params);
      const hash = await walletClient.writeContract(simulationResult.request);
      const receipt = await publicClient.waitForTransactionReceipt({ hash });
      expect(receipt).to.not.be.null;

      const afterERC20Balance = await publicClient.readContract({
        abi: erc20Abi,
        address: erc20Currency,
        functionName: "balanceOf",
        args: [mockCollector],
      });

      expect(beforeERC20Balance - afterERC20Balance).to.be.equal(
        erc20PricePerToken * quantityToMint,
      );

      const afterCollector1155Balance = await publicClient.readContract({
        abi: zoraCreator1155ImplABI,
        address: targetContract,
        functionName: "balanceOf",
        args: [mockCollector, targetTokenId],
      });
      expect(afterCollector1155Balance).to.be.equal(quantityToMint);
    },
    12 * 1000,
  );
});
