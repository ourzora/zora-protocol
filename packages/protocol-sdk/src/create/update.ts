import {
  zoraCreator1155ImplABI,
  zoraCreatorMerkleMinterStrategyABI,
  zoraCreatorMerkleMinterStrategyAddress,
} from "@zoralabs/protocol-deployments";
import { Address, PublicClient, WalletClient, encodeFunctionData } from "viem";

function constructCallData({
  tokenId,
  saleEnd,
  saleStart,
  merkleRoot,
  fundsRecipient,
}: {
  mintLimit?: string;
  tokenId: bigint;
  saleEnd: bigint;
  saleStart: bigint;
  merkleRoot: `0x${string}`;
  fundsRecipient: Address;
}) {
  const saleData = encodeFunctionData({
    abi: zoraCreatorMerkleMinterStrategyABI,
    functionName: "setSale",
    args: [
      tokenId,
      {
        presaleStart: saleStart,
        presaleEnd: saleEnd,
        fundsRecipient,
        merkleRoot,
      },
    ],
  });

  return saleData;
}

export async function updateAllowListOnContract({
  contractAddress: collectionAddress,
  tokenId,
  chainId,
  saleStart,
  saleEnd,
  merkleRoot,
  fundsRecipient,
  tokenAdmin,
  publicClient,
  walletClient,
}: {
  contractAddress: Address;
  tokenId: bigint;
  chainId: number;
  address: Address;
  saleStart: bigint;
  saleEnd: bigint;
  merkleRoot: `0x${string}`;
  fundsRecipient: Address;
  tokenAdmin: Address;
  publicClient: PublicClient;
  walletClient: WalletClient;
}) {
  const saleData = constructCallData({
    fundsRecipient,
    merkleRoot,
    saleEnd,
    saleStart,
    tokenId,
  });

  const merkleSaleStrategyAddress =
    zoraCreatorMerkleMinterStrategyAddress[
      chainId as keyof typeof zoraCreatorMerkleMinterStrategyAddress
    ];

  const { request } = await publicClient.simulateContract({
    abi: zoraCreator1155ImplABI,
    address: collectionAddress,
    functionName: "callSale",
    args: [tokenId, merkleSaleStrategyAddress, saleData],
    account: tokenAdmin,
  });

  const hash = await walletClient.writeContract(request);

  const receipt = await publicClient.waitForTransactionReceipt({
    hash,
  });

  if (receipt.status !== "success") {
    throw new Error("Transaction failed");
  }
}
