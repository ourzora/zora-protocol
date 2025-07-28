import { coinABI } from "@zoralabs/protocol-deployments";
import { GenericPublicClient } from "../utils/genericPublicClient";
import { validateClientNetwork } from "../utils/validateClientNetwork";
import { Address, zeroAddress } from "viem";

/**
 * Represents the current state of a coin
 * @typedef {Object} OnchainCoinDetails
 * @property {bigint} balance - The user's balance of the coin
 * @property {PricingResult} marketCap - The market cap of the coin
 * @property {PricingResult} liquidity - The liquidity of the coin
 * @property {Address} pool - Pool address
 * @property {Slot0Result} poolState - Current state of the UniswapV3 pool
 * @property {Address[]} owners - List of owners for the coin
 * @property {Address} payoutRecipient - The payout recipient address
 */
export type OnchainCoinDetails = {
  balance: bigint;
  owners: readonly Address[];
  payoutRecipient: Address;
};

/**
 * Gets the current state of a coin for a user
 * @param {Object} params - The query parameters
 * @param {Address} params.coin - The coin contract address
 * @param {Address} params.user - The user address to check balance for
 * @param {PublicClient} params.publicClient - The viem public client instance
 * @returns {Promise<OnchainCoinDetails>} The coin's current state
 */
export async function getOnchainCoinDetails({
  coin,
  user = zeroAddress,
  publicClient,
}: {
  coin: Address;
  user?: Address;
  publicClient: GenericPublicClient;
}): Promise<OnchainCoinDetails> {
  validateClientNetwork(publicClient);
  const [balance, owners, payoutRecipient] = await publicClient.multicall({
    contracts: [
      {
        address: coin,
        abi: coinABI,
        functionName: "balanceOf",
        args: [user],
      },
      {
        address: coin,
        abi: coinABI,
        functionName: "owners",
      },
      {
        address: coin,
        abi: coinABI,
        functionName: "payoutRecipient",
      },
    ],
    allowFailure: false,
  });

  return {
    balance,
    owners,
    payoutRecipient,
  };
}
