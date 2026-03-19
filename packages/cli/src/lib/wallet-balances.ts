import { getTokenInfo } from "@zoralabs/coins-sdk";
import {
  createPublicClient,
  erc20Abi,
  formatUnits,
  http,
  type Address,
} from "viem";
import { base } from "viem/chains";
import { formatUsd } from "./format.js";
import { trimTrailingZeros } from "./balance-format.js";
import {
  WETH_ADDRESS,
  USDC_ADDRESS,
  USDC_DECIMALS,
  ZORA_ADDRESS,
  BASE_CHAIN_ID,
} from "./constants.js";

export type WalletBalance = {
  name: string;
  symbol: string;
  balance: string;
  usdValue: string;
};

export type WalletBalanceJson = {
  name: string;
  symbol: string;
  address: string | null;
  balance: string;
  priceUsd: number | null;
  usdValue: number | null;
};

type TokenConfig = {
  name: string;
  symbol: string;
  address: Address;
  decimals: number;
  /** Address used to look up price (e.g. WETH for ETH) */
  priceAddress: Address;
  /** Native token (ETH) — fetched via getBalance instead of ERC20 balanceOf */
  isNative?: boolean;
  /** Fixed USD price (e.g. USDC = $1); skips price lookup */
  fixedPriceUsd?: number;
};

const TRACKED_TOKENS: TokenConfig[] = [
  {
    name: "Ether",
    symbol: "ETH",
    address: WETH_ADDRESS,
    decimals: 18,
    priceAddress: WETH_ADDRESS,
    isNative: true,
  },
  {
    name: "USD Coin",
    symbol: "USDC",
    address: USDC_ADDRESS,
    decimals: USDC_DECIMALS,
    priceAddress: USDC_ADDRESS,
    fixedPriceUsd: 1,
  },
  {
    name: "ZORA",
    symbol: "ZORA",
    address: ZORA_ADDRESS,
    decimals: 18,
    priceAddress: ZORA_ADDRESS,
  },
];

const fetchTokenPriceUsd = async (
  address: string,
  chainId = BASE_CHAIN_ID,
): Promise<number | null> => {
  try {
    const res = await getTokenInfo({ query: { address, chainId } });
    return res.data?.erc20Token?.currency?.priceUsd
      ? Number(res.data.erc20Token.currency.priceUsd)
      : null;
  } catch (err) {
    console.warn(
      `Warning: failed to fetch price for ${address}: ${err instanceof Error ? err.message : String(err)}`,
    );
    return null;
  }
};

type ResolvedToken = {
  token: TokenConfig;
  balance: bigint;
  priceUsd: number | null;
};

export const fetchWalletBalances = async (
  walletAddress: Address,
): Promise<{
  walletBalances: WalletBalance[];
  walletBalancesJson: WalletBalanceJson[];
}> => {
  const publicClient = createPublicClient({ chain: base, transport: http() });

  const nativeToken = TRACKED_TOKENS.find((t) => t.isNative);
  const erc20Tokens = TRACKED_TOKENS.filter((t) => !t.isNative);

  const [ethBalance, multicallResults] = await Promise.all([
    publicClient.getBalance({ address: walletAddress }),
    publicClient.multicall({
      contracts: erc20Tokens.map((t) => ({
        address: t.address,
        abi: erc20Abi,
        functionName: "balanceOf" as const,
        args: [walletAddress] as const,
      })),
    }),
  ]);

  const rawBalances = new Map<TokenConfig, bigint>();
  if (nativeToken) rawBalances.set(nativeToken, ethBalance);
  erc20Tokens.forEach((token, i) => {
    if (multicallResults[i].status === "success") {
      rawBalances.set(token, multicallResults[i].result as bigint);
    } else {
      console.warn(`Warning: failed to fetch balance for ${token.symbol}`);
      rawBalances.set(token, 0n);
    }
  });

  const priceResults = await Promise.allSettled(
    TRACKED_TOKENS.map(async (token) => {
      const balance = rawBalances.get(token) ?? 0n;
      let priceUsd: number | null = null;
      if (token.fixedPriceUsd != null) {
        priceUsd = token.fixedPriceUsd;
      } else if (balance > 0n || token.isNative) {
        priceUsd = await fetchTokenPriceUsd(token.priceAddress);
      }
      return { token, balance, priceUsd };
    }),
  );

  const resolved: ResolvedToken[] = priceResults.map((result, i) => {
    if (result.status === "fulfilled") return result.value;
    const token = TRACKED_TOKENS[i];
    console.warn(`Warning: failed to resolve token ${token.symbol}`);
    return { token, balance: rawBalances.get(token) ?? 0n, priceUsd: null };
  });

  const visible = resolved.filter((r) => r.balance > 0n || r.token.isNative);

  const intermediate = visible.map(({ token, balance, priceUsd }) => {
    const human = formatUnits(balance, token.decimals);
    const usdValue = priceUsd !== null ? Number(human) * priceUsd : null;
    return { token, human, priceUsd, usdValue };
  });

  const walletBalances: WalletBalance[] = intermediate.map(
    ({ token, human, usdValue }) => ({
      name: token.name,
      symbol: token.symbol,
      balance: trimTrailingZeros(human),
      usdValue: usdValue !== null ? formatUsd(usdValue) : "-",
    }),
  );

  const walletBalancesJson: WalletBalanceJson[] = intermediate.map(
    ({ token, human, priceUsd, usdValue }) => ({
      name: token.name,
      symbol: token.symbol,
      address: token.isNative ? null : token.address,
      balance: trimTrailingZeros(human),
      priceUsd,
      usdValue: usdValue !== null ? Number(usdValue.toFixed(6)) : null,
    }),
  );

  return { walletBalances, walletBalancesJson };
};
