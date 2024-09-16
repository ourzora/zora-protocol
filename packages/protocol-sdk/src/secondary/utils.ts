import { Address } from "viem";
import { PublicClient } from "src/utils";
import {
  zoraTimedSaleStrategyABI,
  zoraTimedSaleStrategyAddress,
} from "@zoralabs/protocol-deployments";
import { SecondaryInfo } from "./types";
export async function getSecondaryInfo({
  contract,
  tokenId,
  publicClient,
  chainId,
}: {
  contract: Address;
  tokenId: bigint;
  publicClient: PublicClient;
  chainId: number;
}): Promise<SecondaryInfo | undefined> {
  const result = await publicClient.readContract({
    abi: zoraTimedSaleStrategyABI,
    address:
      zoraTimedSaleStrategyAddress[
        chainId as keyof typeof zoraTimedSaleStrategyAddress
      ],
    functionName: "sale",
    args: [contract, tokenId],
  });

  // if there is no erc20zAddress, we can assume that secondary market has not been configured for this contract and token.
  if (!result.erc20zAddress) {
    return undefined;
  }

  return {
    erc20z: result.erc20zAddress,
    pool: result.poolAddress,
    secondaryActivated: result.secondaryActivated,
    saleEnd: result.saleEnd === 0n ? undefined : result.saleEnd,
  };
}
