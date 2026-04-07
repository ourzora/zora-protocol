import { Address, parseEther } from "viem";
import { PublicClient } from "src/utils";
import {
  zoraTimedSaleStrategyABI,
  zoraTimedSaleStrategyAddress,
} from "@zoralabs/protocol-deployments";
import { SecondaryInfo } from "./types";

const LEGACY_MINIMUM_MARKET_ETH = parseEther("0.0123321");
const LEGACY_MARKET_REWARD = parseEther("0.0000111");
const MARKET_REWARD = parseEther("0.0000222");

export async function getSecondaryInfo({
  contract,
  tokenId,
  publicClient,
}: {
  contract: Address;
  tokenId: bigint;
  publicClient: PublicClient;
}): Promise<SecondaryInfo | undefined> {
  let result;

  const chainId = publicClient.chain.id;

  try {
    result = await publicClient.readContract({
      abi: zoraTimedSaleStrategyABI,
      address:
        zoraTimedSaleStrategyAddress[
          chainId as keyof typeof zoraTimedSaleStrategyAddress
        ],
      functionName: "saleV2",
      args: [contract, tokenId],
    });
  } catch (e) {
    console.error(e);
    return undefined;
  }

  // if there is no erc20zAddress, we can assume that secondary market has not been configured for this contract and token.
  if (!result.erc20zAddress) {
    return undefined;
  }

  const usesLegacyMarketReward =
    result.minimumMarketEth === LEGACY_MINIMUM_MARKET_ETH;
  const erc20zBalance = await publicClient.getBalance({
    address: result.erc20zAddress,
  });

  return {
    erc20z: result.erc20zAddress,
    pool: result.poolAddress,
    secondaryActivated: result.secondaryActivated,
    saleEnd: result.saleEnd === 0n ? undefined : result.saleEnd,
    saleStart: result.saleStart,
    name: result.name,
    symbol: result.symbol,
    marketCountdown:
      result.marketCountdown === 0n ? undefined : result.marketCountdown,
    minimumMintsForCountdown:
      result.minimumMarketEth === 0n
        ? undefined
        : usesLegacyMarketReward
          ? result.minimumMarketEth / LEGACY_MARKET_REWARD
          : result.minimumMarketEth / MARKET_REWARD,
    mintCount: usesLegacyMarketReward
      ? erc20zBalance / LEGACY_MARKET_REWARD
      : erc20zBalance / MARKET_REWARD,
  };
}
