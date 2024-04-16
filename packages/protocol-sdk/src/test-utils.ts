import {
  zoraCreator1155FactoryImplABI,
  zoraCreator1155FactoryImplAddress,
} from "@zoralabs/protocol-deployments";
import {
  Address,
  Hex,
  PublicClient,
  encodeAbiParameters,
  parseAbiParameters,
} from "viem";
import { expect } from "vitest";

export const waitForSuccess = async (hash: Hex, publicClient: PublicClient) => {
  const receipt = await publicClient.waitForTransactionReceipt({
    hash,
  });

  expect(receipt.status).toBe("success");
};

export const getFixedPricedMinter = async ({
  publicClient,
  chainId,
}: {
  publicClient: PublicClient;
  chainId: keyof typeof zoraCreator1155FactoryImplAddress;
}) =>
  await publicClient.readContract({
    abi: zoraCreator1155FactoryImplABI,
    address: zoraCreator1155FactoryImplAddress[chainId],
    functionName: "fixedPriceMinter",
  });

export const fixedPriceMinterMinterArguments = ({
  mintRecipient,
}: {
  mintRecipient: Address;
}) => encodeAbiParameters(parseAbiParameters("address"), [mintRecipient]);
