import { expect } from "vitest";
import { Hex } from "viem/_types/types/misc";
import { PublicClient } from "viem";

export const waitForSuccess = async (hash: Hex, publicClient: PublicClient) => {
  const receipt = await publicClient.waitForTransactionReceipt({
    hash,
  });

  expect(receipt.status).toBe("success");

  return receipt;
};
