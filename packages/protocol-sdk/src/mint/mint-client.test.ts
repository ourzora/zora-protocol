import {
  parseAbi,
  parseEther,
} from "viem";
import { zora } from "viem/chains";
import { describe, expect } from "vitest";
import { MintClient } from "./mint-client";
import { zoraCreator1155ImplABI } from "@zoralabs/protocol-deployments";
import { anvilTest } from "src/anvil";

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
      const targetContract = "0xa2fea3537915dc6c7c7a97a82d1236041e6feb2e";
      const targetTokenId = 1n;
      const minter = new MintClient(zora);

      const { prepared } = await minter.prepareMintToken({
        address: targetContract,
        tokenId: targetTokenId,
        publicClient,
        sender: creatorAccount,
        mintArguments: {
          mintToAddress: creatorAccount,
          quantityToMint: 1,
        },
      });

      const oldBalance = await publicClient.readContract({
        abi: zoraCreator1155ImplABI,
        address: targetContract,
        functionName: "balanceOf",
        args: [creatorAccount, targetTokenId],
      });

      const simulationResult = await publicClient.simulateContract(prepared);

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

  anvilTest(
    "mints a new 721 token",
    async ({ viemClients }) => {
      const { testClient, walletClient, publicClient } = viemClients;
      const creatorAccount = (await walletClient.getAddresses())[0]!;
      await testClient.setBalance({
        address: creatorAccount,
        value: parseEther("2000"),
      });

      const targetContract = "0x7aae7e67515A2CbB8585C707Ca6db37BDd3EA839";
      const targetTokenId = undefined;
      const minter = new MintClient(zora);

      const { prepared } = await minter.prepareMintToken({
        address: targetContract,
        tokenId: targetTokenId,
        publicClient,
        sender: creatorAccount,
        mintArguments: {
          mintToAddress: creatorAccount,
          quantityToMint: 1,
        },
      });
      const oldBalance = await publicClient.readContract({
        abi: erc721ABI,
        address: targetContract,
        functionName: "balanceOf",
        args: [creatorAccount],
      });
      
      const simulated = await publicClient.simulateContract(prepared);

      const hash = await walletClient.writeContract(simulated.request);

      const receipt = await publicClient.getTransactionReceipt({ hash });
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
});
