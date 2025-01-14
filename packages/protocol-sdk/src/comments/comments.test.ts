import { describe, expect } from "vitest";
import { forkUrls, makeAnvilTest } from "src/anvil";
import { writeContractWithRetries } from "src/test-utils";
import { base, zora } from "viem/chains";
import {
  commentsABI,
  commentsAddress,
  emptyCommentIdentifier,
  PermitComment,
  PermitSparkComment,
  sparkValue,
  CommentIdentifier,
  permitSparkCommentTypedDataDefinition,
  permitMintAndCommentTypedDataDefinition,
  PermitMintAndComment,
  callerAndCommenterAddress as callerAndCommenterAddresses,
  callerAndCommenterABI,
  zoraCreator1155ImplABI,
} from "@zoralabs/protocol-deployments";
import {
  Address,
  zeroAddress,
  parseEther,
  TransactionReceipt,
  parseEventLogs,
  hashTypedData,
} from "viem";
import { waitForSuccess } from "src/waitForSuccess";
import { randomNewContract } from "src/test-utils";
import { permitCommentTypedDataDefinition } from "@zoralabs/protocol-deployments";
import { demoTokenMetadataURI } from "src/fixtures/contract-setup";
import { randomNonce, thirtySecondsFromNow } from "src/test-utils";
import { create1155 } from "src/create/create-client";

const getCommentIdentifierFromReceipt = (
  receipt: TransactionReceipt,
): CommentIdentifier => {
  const logs = parseEventLogs({
    abi: commentsABI,
    logs: receipt.logs,
    eventName: "Commented",
  });

  if (logs.length === 0) {
    throw new Error("No Commented event found in receipt");
  }

  return logs[0]!.args.commentIdentifier;
};

// todo: move this to protocol-deployments
describe("comments", () => {
  makeAnvilTest({
    forkUrl: forkUrls.zoraMainnet,
    forkBlockNumber: 21297211,
    anvilChainId: zora.id,
  })(
    "can sign and execute a cross-chain comment, and sign and execute a cross-chain spark comment",
    async ({
      viemClients: { publicClient, walletClient, chain, testClient },
    }) => {
      // Get the chain ID and set up addresses for different roles
      const chainId = chain.id;
      const [
        collectorAddress,
        creatorAddress,
        executorAddress,
        sparkerAddress,
      ] = (await walletClient.getAddresses()!) as [
        Address,
        Address,
        Address,
        Address,
      ];

      // Step 1: Create a new 1155 contract and token
      const { contractAddress, newTokenId, parameters, prepareMint } =
        await create1155({
          contract: randomNewContract(),
          token: {
            tokenMetadataURI: demoTokenMetadataURI,
          },
          account: creatorAddress,
          publicClient,
        });

      // Deploy the new contract
      const { request } = await publicClient.simulateContract(parameters);
      await writeContractWithRetries({
        request,
        walletClient,
        publicClient,
      });

      // Prepare to mint a token
      const { parameters: collectParameters } = await prepareMint({
        quantityToMint: 1n,
        minterAccount: collectorAddress,
      });

      // Step 2: Mint an 1155 token on the new contract
      const { request: mintRequest } =
        await publicClient.simulateContract(collectParameters);
      await writeContractWithRetries({
        request: mintRequest,
        walletClient,
        publicClient,
      });

      // Set up cross-chain comment parameters
      const sourceChainId = base.id; // The chain ID where the comment originates

      const commentsAddressForChainId =
        commentsAddress[chainId as keyof typeof commentsAddress];

      // Step 3: Prepare a cross-chain comment
      const permitComment: PermitComment = {
        sourceChainId,
        contractAddress,
        destinationChainId: chainId,
        tokenId: newTokenId,
        commenter: collectorAddress,
        text: "hello world",
        deadline: thirtySecondsFromNow(),
        nonce: randomNonce(),
        referrer: zeroAddress,
        commenterSmartWallet: zeroAddress,
        replyTo: emptyCommentIdentifier(),
      };

      // Generate typed data for signing
      const typedData = permitCommentTypedDataDefinition(permitComment);

      expect(typedData.domain!.chainId).toEqual(sourceChainId);
      expect(typedData.account).toEqual(collectorAddress);
      expect(typedData.domain!.verifyingContract).toEqual(
        commentsAddressForChainId,
      );
      expect(typedData.domain!.verifyingContract).toEqual(
        commentsAddressForChainId,
      );

      const hashed = await publicClient.readContract({
        abi: commentsABI,
        address: commentsAddressForChainId,
        functionName: "hashPermitComment",
        args: [permitComment],
      });

      expect(hashed).toEqual(hashTypedData(typedData));

      // Ensure the commenter has enough balance for the spark value
      await testClient.setBalance({
        address: collectorAddress,
        value: sparkValue(),
      });

      // Step 4: Sign the cross-chain comment
      const signature = await walletClient.signTypedData(typedData);

      // Ensure the executor has enough balance to execute the transaction
      await testClient.setBalance({
        address: executorAddress,
        value: parseEther("1"),
      });

      // Step 5: Simulate and execute the cross-chain comment
      const { request: commentRequest } = await publicClient.simulateContract({
        abi: commentsABI,
        address: commentsAddressForChainId,
        functionName: "permitComment",
        args: [permitComment, signature],
        account: executorAddress,
        value: sparkValue(),
      });

      const commentHash = await walletClient.writeContract(commentRequest);
      const receipt = await publicClient.waitForTransactionReceipt({
        hash: commentHash,
      });

      expect(receipt.status).toBe("success");

      // Extract the comment identifier from the transaction receipt
      const commentIdentifier = getCommentIdentifierFromReceipt(receipt);

      // Step 6: Prepare a spark (like) for the comment
      const sparkComment: PermitSparkComment = {
        sparksQuantity: 3n,
        sparker: sparkerAddress,
        deadline: thirtySecondsFromNow(),
        nonce: randomNonce(),
        referrer: zeroAddress,
        sourceChainId,
        destinationChainId: chainId,
        comment: commentIdentifier,
      };

      const sparkTypedData =
        permitSparkCommentTypedDataDefinition(sparkComment);

      // Step 7: Sign the spark comment
      const sparkSignature = await walletClient.signTypedData(sparkTypedData);

      // Step 8: Simulate and execute the spark comment
      const { request: sparkRequest } = await publicClient.simulateContract({
        abi: commentsABI,
        address: commentsAddressForChainId,
        functionName: "permitSparkComment",
        args: [sparkComment, sparkSignature],
        account: executorAddress,
        value: sparkValue() * sparkComment.sparksQuantity,
      });

      const sparkHash = await walletClient.writeContract(sparkRequest);

      await waitForSuccess(sparkHash, publicClient);

      // Step 9: Verify the spark count
      const sparkCount = await publicClient.readContract({
        abi: commentsABI,
        address: commentsAddressForChainId,
        functionName: "commentSparksQuantity",
        args: [commentIdentifier],
      });

      expect(sparkCount).toEqual(sparkComment.sparksQuantity);
    },
    40_000,
  );
  makeAnvilTest({
    forkUrl: forkUrls.zoraMainnet,
    forkBlockNumber: 21297211,
    anvilChainId: zora.id,
  })(
    "can sign and execute a cross-chain timed sale mint and comment",
    async ({
      viemClients: { publicClient, walletClient, chain, testClient },
    }) => {
      // Get the chain ID and set up addresses for different roles
      const chainId = chain.id;
      const [commenterAddress, executorAddress] =
        (await walletClient.getAddresses()!) as [Address, Address, Address];

      // Step 1: Create a new 1155 contract and token
      const { contractAddress, newTokenId, parameters } = await create1155({
        contract: randomNewContract(),
        token: {
          tokenMetadataURI: demoTokenMetadataURI,
        },
        account: commenterAddress,
        publicClient,
      });

      // Deploy the new contract
      const { request } = await publicClient.simulateContract(parameters);
      await writeContractWithRetries({
        request,
        walletClient,
        publicClient,
      });

      // Step 2: Prepare the permit data for timed sale mint and comment
      const quantity = 3n;
      const mintReferral = zeroAddress;
      const comment = "This is a test comment for timed sale mint";

      const permitMintAndComment: PermitMintAndComment = {
        commenter: commenterAddress,
        quantity,
        collection: contractAddress,
        tokenId: newTokenId,
        mintReferral,
        comment,
        deadline: thirtySecondsFromNow(),
        nonce: randomNonce(),
        sourceChainId: chainId,
        destinationChainId: chainId,
      };

      // Step 3: Generate the typed data for signing
      const typedData =
        permitMintAndCommentTypedDataDefinition(permitMintAndComment);

      // Step 4: Sign the typed data
      const signature = await walletClient.signTypedData(typedData);

      await testClient.setBalance({
        address: executorAddress,
        value: parseEther("1"),
      });

      // Step 5: Simulate and execute the permitTimedSaleMintAndComment function
      const callerAndCommenterAddress =
        callerAndCommenterAddresses[
          chainId as keyof typeof callerAndCommenterAddresses
        ];
      const { request: permitRequest } = await publicClient.simulateContract({
        abi: callerAndCommenterABI,
        address: callerAndCommenterAddress,
        functionName: "permitTimedSaleMintAndComment",
        args: [permitMintAndComment, signature],
        account: executorAddress,
        value: quantity * parseEther("0.000111"),
      });

      const receipt = await writeContractWithRetries({
        publicClient,
        walletClient,
        request: permitRequest,
      });

      // Step 6: Verify the comment was created
      const commentIdentifier = getCommentIdentifierFromReceipt(receipt);
      expect(commentIdentifier).toBeDefined();

      // Step 7: Verify the token was minted
      const balance = await publicClient.readContract({
        abi: zoraCreator1155ImplABI,
        address: contractAddress,
        functionName: "balanceOf",
        args: [commenterAddress, newTokenId],
      });

      expect(balance).toEqual(quantity);
    },
    40_000, // Increased timeout to 30 seconds
  );
});
