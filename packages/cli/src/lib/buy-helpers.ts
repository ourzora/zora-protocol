import {
  parseEther,
  formatEther,
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

const amountModeChecks = {
  eth: (opts: { eth?: string }) => opts.eth !== undefined,
  percent: (opts: { percent?: string }) => opts.percent !== undefined,
  all: (opts: { all?: boolean }) => opts.all === true,
} as const;

export type AmountMode = keyof typeof amountModeChecks;

export const getAmountMode = (
  json: boolean,
  opts: { eth?: string; percent?: string; all?: boolean },
): AmountMode => {
  const provided = (
    Object.entries(amountModeChecks) as Array<
      [AmountMode, (typeof amountModeChecks)[AmountMode]]
    >
  )
    .filter(([, isProvided]) => isProvided(opts))
    .map(([mode]) => mode);

  if (provided.length === 0) {
    outputErrorAndExit(
      json,
      "Specify one amount flag: --eth, --percent, or --all",
    );
  }

  if (provided.length > 1) {
    outputErrorAndExit(json, "Only one amount flag allowed.");
  }

  return provided[0]!;
};

export const parsePercentageLikeValue = (value: string): number | undefined => {
  if (!/^\d+(\.\d+)?$/.test(value)) return undefined;

  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : undefined;
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

export type QuoteInfo = {
  coinName: string;
  coinSymbol: string;
  address: string;
  ethAmount: string;
  amountIn: bigint;
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
        eth: formatEther(info.amountIn),
        wei: info.amountIn.toString(),
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
  console.log(`   Amount       ${info.ethAmount} ETH`);
  console.log(`   You get      ~${info.coinsFormatted} ${info.coinSymbol}`);
  console.log(`   Slippage     ${info.slippagePct}%\n`);
};

export type TradeResultInfo = {
  coinName: string;
  coinSymbol: string;
  address: string;
  ethAmount: string;
  amountIn: bigint;
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
        eth: formatEther(info.amountIn),
        wei: info.amountIn.toString(),
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
  console.log(`   Spent        ${info.ethAmount} ETH`);
  console.log(`   Received     ${receivedFormatted} ${info.coinSymbol}`);
  console.log(`   Tx           ${info.txHash}\n`);
};
