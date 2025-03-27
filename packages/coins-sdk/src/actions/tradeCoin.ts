import { coinABI } from "@zoralabs/coins";
import { validateClientNetwork } from "../utils/validateClientNetwork";
import {
  Address,
  TransactionReceipt,
  WalletClient,
  SimulateContractParameters,
  parseEther,
  zeroAddress,
  ContractEventArgsFromTopics,
  parseEventLogs,
} from "viem";
import { baseSepolia } from "viem/chains";
import { GenericPublicClient } from "src/utils/genericPublicClient";
// Define trade event args type

export type SellEventArgs = ContractEventArgsFromTopics<
  typeof coinABI,
  "CoinSell"
>;
export type BuyEventArgs = ContractEventArgsFromTopics<
  typeof coinABI,
  "CoinBuy"
>;

export type TradeEventArgs = SellEventArgs | BuyEventArgs;

/**
 * Simulates a buy order to get the expected output amount
 * @param {Object} params - The simulation parameters
 * @param {Address} params.target - The target coin contract address
 * @param {bigint} params.requestedOrderSize - The desired input amount for the buy
 * @param {PublicClient} params.publicClient - The viem public client instance
 * @returns {Promise<{orderSize: bigint, amountOut: bigint}>} The simulated order size and output amount
 */
export async function simulateBuy({
  target,
  requestedOrderSize,
  publicClient,
}: {
  target: Address;
  requestedOrderSize: bigint;
  publicClient: GenericPublicClient;
}): Promise<{ orderSize: bigint; amountOut: bigint }> {
  const numberResult = await publicClient.simulateContract({
    address: target,
    abi: coinABI,
    functionName: "buy",
    args: [
      zeroAddress,
      requestedOrderSize,
      0n, // minAmountOut
      0n, // sqrtPriceLimitX96
      zeroAddress, // tradeReferrer
    ],
    // We want to ensure that the multicall3 contract has enough ETH to buy in the simulation
    stateOverride: [
      {
        address: baseSepolia.contracts.multicall3.address,
        balance: parseEther("10000000"),
      },
    ],
  });
  const orderSize = numberResult.result[0];
  const amountOut = numberResult.result[1];
  return { orderSize, amountOut };
}

/**
 * Parameters for creating a trade call
 * @typedef {Object} TradeParams
 * @property {'sell' | 'buy'} direction - The trade direction
 * @property {Address} target - The target coin contract address
 * @property {Object} args - The trade arguments
 * @property {Address} args.recipient - The recipient of the trade output
 * @property {bigint} args.orderSize - The size of the order
 * @property {bigint} [args.minAmountOut] - The minimum amount to receive
 * @property {bigint} [args.sqrtPriceLimitX96] - The price limit for the trade
 * @property {Address} [args.tradeReferrer] - The referrer address for the trade
 */
export type TradeParams = {
  direction: "sell" | "buy";
  target: Address;
  args: {
    recipient: Address;
    orderSize: bigint;
    minAmountOut?: bigint;
    sqrtPriceLimitX96?: bigint;
    tradeReferrer?: Address;
  };
};

/**
 * Creates a trade call parameters object for buy or sell
 * @param {TradeParams} params - The trade parameters
 * @returns {SimulateContractParameters} The contract call parameters
 */
export function tradeCoinCall({
  target,
  direction,
  args: {
    recipient,
    orderSize,
    minAmountOut = 0n,
    sqrtPriceLimitX96 = 0n,
    tradeReferrer = zeroAddress,
  },
}: TradeParams): SimulateContractParameters {
  return {
    abi: coinABI,
    functionName: direction,
    address: target,
    args: [
      recipient,
      orderSize,
      minAmountOut,
      sqrtPriceLimitX96,
      tradeReferrer,
    ],
    value: direction === "buy" ? orderSize : 0n,
  } as const;
}

/**
 * Gets the trade event from transaction receipt logs
 * @param {TransactionReceipt} receipt - The transaction receipt containing the logs
 * @param {'buy' | 'sell'} direction - The direction of the trade
 * @returns {TradeEventArgs | undefined} The decoded trade event args if found
 */
export function getTradeFromLogs(
  receipt: TransactionReceipt,
  direction: "buy" | "sell",
): TradeEventArgs | undefined {
  const eventLogs = parseEventLogs({
    abi: coinABI,
    logs: receipt.logs,
  });

  if (direction === "buy") {
    return eventLogs.find((log) => log.eventName === "CoinBuy")?.args;
  }
  return eventLogs.find((log) => log.eventName === "CoinSell")?.args;
}

/**
 * Executes a trade transaction
 * @param {TradeParams} params - The trade parameters
 * @param {PublicClient} publicClient - The viem public client instance
 * @param {WalletClient} walletClient - The viem wallet client instance
 * @returns {Promise<{
 *   hash: `0x${string}`,
 *   receipt: TransactionReceipt,
 *   trade: TradeEventArgs | undefined
 * }>} The transaction result with trade details
 */
export async function tradeCoin(
  params: TradeParams,
  walletClient: WalletClient,
  publicClient: GenericPublicClient,
) {
  validateClientNetwork(publicClient);
  const { request } = await publicClient.simulateContract({
    ...tradeCoinCall(params),
    account: walletClient.account,
  });
  const hash = await walletClient.writeContract(request);
  const receipt = await publicClient.waitForTransactionReceipt({ hash });
  const trade = getTradeFromLogs(receipt, params.direction);

  return {
    hash,
    receipt,
    trade,
  };
}
