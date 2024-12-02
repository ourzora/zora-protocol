import {
  zoraCreator1155FactoryImplABI,
  zoraCreator1155FactoryImplAddress,
} from "@zoralabs/protocol-deployments";
import {
  Address,
  Hex,
  PublicClient,
  encodeAbiParameters,
  keccak256,
  toBytes,
  parseAbiParameters,
} from "viem";
import { NewContractParams } from "./create/types";
import { expect } from "vitest";

export const waitForSuccess = async (hash: Hex, publicClient: PublicClient) => {
  const receipt = await publicClient.waitForTransactionReceipt({
    hash,
  });

  expect(receipt.status).toBe("success");

  return receipt;
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

const demoContractMetadataURI = "ipfs://DUMMY/contract.json";

export function randomNewContract(): NewContractParams {
  return {
    name: `testContract-${Math.round(Math.random() * 1_000_000)}`,
    uri: demoContractMetadataURI,
  };
}

export const randomNonce = () =>
  keccak256(toBytes(Math.round(Math.random() * 1000)));
export const thirtySecondsFromNow = () =>
  BigInt(Math.round(new Date().getTime() / 1000)) + 30n;
