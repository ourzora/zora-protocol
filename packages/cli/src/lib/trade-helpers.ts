import {
  parseEther,
  formatUnits,
  isAddressEqual,
  parseEventLogs,
  erc20Abi,
  type Address,
  type TransactionReceipt,
} from "viem";
import { outputErrorAndExit, outputJson } from "./output.js";
import { formatCoinsDisplay } from "./format.js";

export const GAS_RESERVE = parseEther("0.001");

export const BUY_AMOUNT_CHECKS = {
  eth: (opts: Record<string, unknown>) => opts.eth !== undefined,
  usd: (opts: Record<string, unknown>) => opts.usd !== undefined,
  percent: (opts: Record<string, unknown>) => opts.percent !== undefined,
  all: (opts: Record<string, unknown>) => opts.all === true,
} as const;

export const SELL_AMOUNT_CHECKS = {
  amount: (opts: Record<string, unknown>) => opts.amount !== undefined,
  usd: (opts: Record<string, unknown>) => opts.usd !== undefined,
  percent: (opts: Record<string, unknown>) => opts.percent !== undefined,
  all: (opts: Record<string, unknown>) => opts.all === true,
} as const;

export type BuyAmountMode = keyof typeof BUY_AMOUNT_CHECKS;
export type SellAmountMode = keyof typeof SELL_AMOUNT_CHECKS;

export const getAmountMode = <M extends string>(
  json: boolean,
  opts: Record<string, unknown>,
  checks: Record<M, (opts: Record<string, unknown>) => boolean>,
  flagNames: string,
): M => {
  const provided = (
    Object.entries(checks) as Array<
      [M, (opts: Record<string, unknown>) => boolean]
    >
  )
    .filter(([, isProvided]) => isProvided(opts))
    .map(([mode]) => mode);

  if (provided.length === 0) {
    outputErrorAndExit(json, `Specify one amount flag: ${flagNames}`);
  }

  if (provided.length > 1) {
    outputErrorAndExit(json, `Only one amount flag allowed: ${flagNames}`);
  }

  return provided[0]!;
};

export const parsePercentageLikeValue = (value: string): number | undefined => {
  if (!/^\d+(\.\d+)?$/.test(value)) return undefined;

  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : undefined;
};

export const formatAmountDisplay = (
  amount: bigint,
  decimals: number,
): string => {
  const formatted = formatUnits(amount, decimals);
  const parts = formatted.split(".");
  const truncated = parts[1]
    ? `${parts[0]}.${parts[1].slice(0, 2)}`
    : formatted;
  return new Intl.NumberFormat("en-US", {
    maximumFractionDigits: 2,
  }).format(Number(truncated));
};

export const getReceivedAmountFromReceipt = ({
  receipt,
  tokenAddress,
  recipient,
}: {
  receipt: TransactionReceipt;
  tokenAddress: Address;
  recipient: Address;
}): bigint => {
  const transfers = parseEventLogs({
    abi: erc20Abi,
    eventName: "Transfer",
    logs: receipt.logs,
    strict: false,
  });

  const matchingTransfers = transfers.filter((transfer) => {
    const to = transfer.args?.to;
    if (!to) return false;

    return (
      isAddressEqual(transfer.address, tokenAddress) &&
      isAddressEqual(to, recipient)
    );
  });

  if (matchingTransfers.length === 0) {
    throw new Error("No matching Transfer event found in receipt.");
  }

  return matchingTransfers.reduce((total, transfer) => {
    const value = transfer.args?.value;
    if (value === undefined) {
      throw new Error("Transfer event missing amount.");
    }
    return total + value;
  }, 0n);
};

export const printDebugRequest = (
  label: string,
  tradeParameters: {
    sell: { type: string; address?: string };
    buy: { type: string; address?: string };
    amountIn: bigint;
    slippage?: number;
    sender: string;
    recipient?: string;
  },
): void => {
  if (process.env.ZORA_API_TARGET) {
    console.error(`[debug] API target: ${process.env.ZORA_API_TARGET}`);
  }
  console.error(`\n[debug] ${label} — Quote Request:`);
  console.error(
    JSON.stringify(
      {
        tokenIn: tradeParameters.sell,
        tokenOut: tradeParameters.buy,
        amountIn: tradeParameters.amountIn.toString(),
        slippage: tradeParameters.slippage,
        chainId: 8453,
        sender: tradeParameters.sender,
        recipient: tradeParameters.recipient || tradeParameters.sender,
      },
      null,
      2,
    ),
  );
};

export const printDebugResponse = (
  label: string,
  quoteResponse: Record<string, unknown>,
): void => {
  console.error(`\n[debug] ${label} — Quote Response:`);
  console.error(JSON.stringify(quoteResponse, null, 2));
  console.error("");
};

export type QuoteInfo = {
  coinName: string;
  coinSymbol: string;
  address: string;
  spendAmount: string;
  amountIn: bigint;
  inputTokenSymbol: string;
  inputTokenDecimals: number;
  coinsFormatted: string;
  amountOut: string;
  slippagePct: number;
};

export const printQuote = (json: boolean, info: QuoteInfo): void => {
  if (json) {
    outputJson({
      action: "quote",
      coin: info.coinSymbol,
      address: info.address,
      spend: {
        amount: formatUnits(info.amountIn, info.inputTokenDecimals),
        raw: info.amountIn.toString(),
        symbol: info.inputTokenSymbol,
      },
      estimated: {
        amount: formatUnits(BigInt(info.amountOut), 18),
        raw: info.amountOut,
        symbol: info.coinSymbol,
      },
      slippage: info.slippagePct,
    });
    return;
  }

  console.log(`\n Buy ${info.coinName} (${info.coinSymbol})\n`);
  console.log(`   Amount       ${info.spendAmount}`);
  console.log(`   You get      ~${info.coinsFormatted} ${info.coinSymbol}`);
  console.log(`   Slippage     ${info.slippagePct}%\n`);
};

export type TradeResultInfo = {
  coinName: string;
  coinSymbol: string;
  address: string;
  spendAmount: string;
  amountIn: bigint;
  inputTokenSymbol: string;
  inputTokenDecimals: number;
  receivedAmountOut: bigint;
  txHash: string;
};

export const printTradeResult = (
  json: boolean,
  info: TradeResultInfo,
): void => {
  const receivedAmount = formatUnits(info.receivedAmountOut, 18);
  const receivedFormatted = formatCoinsDisplay(receivedAmount);

  if (json) {
    outputJson({
      action: "buy",
      coin: info.coinSymbol,
      address: info.address,
      spent: {
        amount: formatUnits(info.amountIn, info.inputTokenDecimals),
        raw: info.amountIn.toString(),
        symbol: info.inputTokenSymbol,
      },
      received: {
        amount: receivedAmount,
        raw: info.receivedAmountOut.toString(),
        symbol: info.coinSymbol,
      },
      tx: info.txHash,
    });
    return;
  }

  console.log(`\n Bought ${info.coinName}\n`);
  console.log(`   Spent        ${info.spendAmount} ${info.inputTokenSymbol}`);
  console.log(`   Received     ${receivedFormatted} ${info.coinSymbol}`);
  console.log(`   Tx           ${info.txHash}\n`);
};
