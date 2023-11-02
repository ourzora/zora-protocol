import {
  Address,
  createPublicClient,
  createTestClient,
  createWalletClient,
  http,
  parseAbi,
  parseEther,
} from "viem";
import { foundry, zora } from "viem/chains";
import { describe, it, beforeEach, expect, afterEach } from "vitest";
import { MintClient } from "./mint-client";
import { zoraCreator1155ImplABI } from "@zoralabs/protocol-deployments";

const chain = foundry;

const walletClient = createWalletClient({
  chain,
  transport: http(),
});

const testClient = createTestClient({
  chain,
  mode: "anvil",
  transport: http(),
});

const publicClient = createPublicClient({
  chain,
  transport: http(),
});

const [creatorAccount] = (await walletClient.getAddresses()) as [Address];

const erc721ABI = parseAbi([
  "function balanceOf(address owner) public view returns (uint256)",
] as const);

describe("mint-helper", () => {
  beforeEach(async () => {
    await testClient.setBalance({
      address: creatorAccount,
      value: parseEther("2000"),
    });
  });
  afterEach(() => testClient.reset());

  it(
    "mints a new 1155 token",
    async () => {
      const targetContract = "0xa2fea3537915dc6c7c7a97a82d1236041e6feb2e";
      const targetTokenId = 1n;
      const minter = new MintClient(zora);

      const { send } = await minter.mintToken({
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
      const hash = await send(walletClient);
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

  it(
    "mints a new 721 token",
    async () => {
      const targetContract = "0x7aae7e67515A2CbB8585C707Ca6db37BDd3EA839";
      const targetTokenId = undefined;
      const minter = new MintClient(zora);

      const { send } = await minter.mintToken({
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
      const hash = await send(walletClient);
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
