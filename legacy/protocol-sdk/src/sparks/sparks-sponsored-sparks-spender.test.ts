import { encodeFunctionData, parseEther } from "viem";
import { zora, base } from "viem/chains";
import { describe, expect } from "vitest";
import { forkUrls, makeAnvilTest } from "src/anvil";
import {
  iSponsoredSparksSpenderActionABI,
  sponsoredSparksSpenderABI,
  zoraSparks1155Address,
  zoraSparksManagerImplAddress,
} from "@zoralabs/protocol-deployments";
import {
  sponsoredSparksSpenderAddress,
  sponsoredSparksBatchTypedDataDefinition,
  SponsoredSparksBatch,
} from "@zoralabs/protocol-deployments";
import { zoraSparks1155ABI } from "@zoralabs/protocol-deployments";
import { zoraSparksManagerImplABI } from "@zoralabs/protocol-deployments";

const anvilTest = makeAnvilTest({
  forkUrl: forkUrls.zoraMainnet,
  anvilChainId: zora.id,
  forkBlockNumber: 22160611,
});
describe("Sponsored Mints Spender with Relay", () => {
  anvilTest(
    "can sponsor a mint and relay the mint to another chain",
    async ({
      viemClients: { testClient, walletClient, publicClient, chain },
    }) => {
      const tokenIds: bigint[] = [1n];
      const quantityToMint = 10_000n;
      const quantitiesToUnwrap: bigint[] = [5_000n];

      const tokenPrice = await publicClient.readContract({
        abi: zoraSparks1155ABI,
        address: zoraSparks1155Address[zora.id],
        functionName: "tokenPrice",
        args: [1n],
      });

      const collector = (await walletClient.getAddresses())[1]!;

      await testClient.setBalance({
        address: collector,
        value: parseEther("10"),
      });

      const { request } = await publicClient.simulateContract({
        abi: zoraSparksManagerImplABI,
        address: zoraSparksManagerImplAddress[zora.id],
        chain,
        account: collector,
        functionName: "mintWithEth",
        args: [1n, quantityToMint, collector],
        value: tokenPrice * quantityToMint,
      });

      const mintHash = await walletClient.writeContract(request);

      expect(
        (
          await publicClient.waitForTransactionReceipt({
            hash: mintHash,
          })
        ).status,
      ).toBe("success");

      const redeemAmount = quantitiesToUnwrap[0]! * tokenPrice;

      // @ts-ignore
      const response = await fetch("https://api.relay.link/execute/bridge", {
        method: "POST",
        body: JSON.stringify({
          user: sponsoredSparksSpenderAddress[zora.id],
          recipient: collector,
          originChainId: zora.id,
          destinationChainId: base.id,
          currency: "eth",
          amount: Number(redeemAmount),
        }),
        headers: {
          accept: "application/json",
          "content-type": "application/json",
        },
      });
      const jsonResponse = await response.json();

      const transactionStep = jsonResponse.steps.find(
        (step: any) => step.kind === "transaction",
      );
      const transactionItem = transactionStep.items[0];

      const verifier = (await walletClient.getAddresses())[0]!;

      const sponsoredCallData: SponsoredSparksBatch = {
        verifier: verifier,
        from: collector,
        destination: transactionItem.data.to,
        data: transactionItem.data.data,
        totalAmount: transactionItem.data.value,
        expectedRedeemAmount: redeemAmount,
        ids: tokenIds,
        quantities: quantitiesToUnwrap,
        nonce: BigInt(Math.floor(Math.random() * 1000000)),
        deadline: BigInt(Math.floor(new Date().getTime() / 1000 + 60)),
      } as const;

      const typedData = sponsoredSparksBatchTypedDataDefinition({
        chainId: zora.id,
        message: sponsoredCallData,
      });

      const owner = await publicClient.readContract({
        abi: sponsoredSparksSpenderABI,
        address: sponsoredSparksSpenderAddress[zora.id],
        functionName: "owner",
      });

      await testClient.impersonateAccount({
        address: owner,
      });

      await testClient.setBalance({
        address: owner,
        value: parseEther("10"),
      });

      const { request: request2 } = await publicClient.simulateContract({
        abi: sponsoredSparksSpenderABI,
        address: sponsoredSparksSpenderAddress[zora.id],
        chain,
        account: owner,
        functionName: "setVerifierStatus",
        args: [verifier, true],
      });

      const hash = await walletClient.writeContract(request2);

      const receipt = await publicClient.waitForTransactionReceipt({
        hash,
      });

      expect(receipt.status).toBe("success");

      const signature = await walletClient.signTypedData({
        ...typedData,
        account: verifier,
      });

      const receiveSignatureFunction = encodeFunctionData({
        abi: iSponsoredSparksSpenderActionABI,
        functionName: "sponsoredMintBatch",
        args: [sponsoredCallData, signature],
      });

      // send user op with safeBatchTransferFrom
      // transferring to the SponsoredMintsSender with calldata to unwrap and spend addt'l ETH to relay
      const writeResponse = await publicClient.simulateContract({
        address: zoraSparks1155Address[zora.id],
        abi: [...zoraSparks1155ABI, ...sponsoredSparksSpenderABI],
        functionName: "safeBatchTransferFrom",
        args: [
          collector,
          sponsoredSparksSpenderAddress[zora.id],
          tokenIds,
          quantitiesToUnwrap,
          receiveSignatureFunction,
        ],
        account: collector,
      });

      const transferHash = await walletClient.writeContract(
        writeResponse.request,
      );

      const transferReceipt = await publicClient.waitForTransactionReceipt({
        hash: transferHash,
      });

      expect(transferReceipt.status).toBe("success");
    },
    20_000,
  );
});
