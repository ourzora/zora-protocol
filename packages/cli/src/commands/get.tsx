import { Command } from "commander";
import { setApiKey } from "@zoralabs/coins-sdk";
import { getApiKey } from "../lib/config.js";
import { getJson, outputErrorAndExit, outputData } from "../lib/output.js";
import {
  parseCoinRef,
  resolveCoin,
  type ResolvedCoin,
} from "../lib/coin-ref.js";
import { renderOnce } from "../lib/render.js";
import { CoinDetail } from "../components/CoinDetail.js";
import type { CoinType } from "../lib/types.js";

function formatCoinJson(coin: ResolvedCoin): Record<string, unknown> {
  return {
    name: coin.name,
    address: coin.address,
    coinType: coin.coinType,
    marketCap: coin.marketCap,
    marketCapDelta24h: coin.marketCapDelta24h,
    volume24h: coin.volume24h,
    uniqueHolders: coin.uniqueHolders,
    createdAt: coin.createdAt ?? null,
    creatorAddress: coin.creatorAddress ?? null,
    creatorHandle: coin.creatorHandle ?? null,
  };
}

const VALID_TYPES: readonly CoinType[] = ["creator-coin", "post", "trend"];

export const getCommand = new Command("get")
  .description("Look up a coin by address or name")
  .argument("<identifier>", "Coin address (0x...) or creator name")
  .option("--type <type>", "Coin type: creator-coin, post, trend")
  .action(async function (
    this: Command,
    identifier: string,
    opts: { type?: string },
  ) {
    const json = getJson(this);

    if (opts.type !== undefined && !VALID_TYPES.includes(opts.type as any)) {
      outputErrorAndExit(
        json,
        `Invalid --type value: ${opts.type}.`,
        `Supported: ${VALID_TYPES.join(", ")}`,
      );
    }

    const type = opts.type as CoinType | undefined;

    if (type === "post" && !identifier.startsWith("0x")) {
      outputErrorAndExit(
        json,
        "Posts can only be looked up by address.",
        "Use: zora get 0x...",
      );
    }

    const ref = parseCoinRef(identifier, opts.type);

    const apiKey = getApiKey();
    if (apiKey) {
      setApiKey(apiKey);
    }

    let result;
    try {
      result = await resolveCoin(ref);
    } catch (err) {
      outputErrorAndExit(
        json,
        `Request failed: ${err instanceof Error ? err.message : String(err)}`,
      );
      return;
    }

    if (type && result.kind === "found" && result.coin.coinType !== type) {
      outputErrorAndExit(
        json,
        `Coin at ${result.coin.address} is a ${result.coin.coinType}, not a ${type}.`,
        `Use: zora get ${result.coin.address} --type ${result.coin.coinType}`,
      );
      return;
    }

    if (result.kind === "not-found") {
      outputErrorAndExit(json, result.message);
      return;
    }

    outputData(json, {
      json: formatCoinJson(result.coin),
      table: () => {
        renderOnce(<CoinDetail coin={result.coin} />);
      },
    });
  });
