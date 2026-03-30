import { Command } from "commander";
import { setApiKey } from "@zoralabs/coins-sdk";
import { getApiKey } from "../lib/config.js";
import { getJson, outputErrorAndExit, outputData } from "../lib/output.js";
import {
  parsePositionalCoinArgs,
  coinArgsToRef,
  resolveAmbiguousName,
  resolveCoin,
  formatAmbiguousError,
  CoinArgError,
  type ResolvedCoin,
} from "../lib/coin-ref.js";
import { renderOnce } from "../lib/render.js";
import { CoinDetail } from "../components/CoinDetail.js";
import { track } from "../lib/analytics.js";
import { apiErrorMessage } from "../lib/errors.js";

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

function outputCoin(json: boolean, coin: ResolvedCoin): void {
  outputData(json, {
    json: formatCoinJson(coin),
    render: () => {
      renderOnce(<CoinDetail coin={coin} />);
    },
  });
}

export const getCommand = new Command("get")
  .description("Look up a coin by address or name")
  .argument("[typeOrId]", "Type prefix (creator-coin, trend) or identifier")
  .argument(
    "[identifier]",
    "Coin address (0x...) or name (when type prefix is given)",
  )
  .action(async function (
    this: Command,
    typeOrId: string,
    identifier: string | undefined,
  ) {
    const json = getJson(this);

    let parsed;
    try {
      parsed = parsePositionalCoinArgs(typeOrId, identifier);
    } catch (err) {
      if (err instanceof CoinArgError) {
        outputErrorAndExit(json, err.message, err.suggestion);
      }
      throw err;
    }

    const apiKey = getApiKey();
    if (apiKey) {
      setApiKey(apiKey);
    }

    if (parsed.kind === "ambiguous-name") {
      let ambResult;
      try {
        ambResult = await resolveAmbiguousName(parsed.name);
      } catch (err) {
        outputErrorAndExit(
          json,
          `Request failed: ${err instanceof Error ? err.message : String(err)}`,
        );
        return;
      }

      if (ambResult.kind === "not-found") {
        outputErrorAndExit(json, ambResult.message);
        return;
      }

      if (ambResult.kind === "ambiguous") {
        if (json) {
          outputData(json, {
            json: {
              matches: [
                { type: "creator-coin", ...formatCoinJson(ambResult.creator) },
                { type: "trend", ...formatCoinJson(ambResult.trend) },
              ],
              hint: `Use: zora get creator-coin ${parsed.name}  or  zora get trend ${parsed.name}`,
            },
            render: () => {},
          });
        } else {
          outputCoin(false, ambResult.creator);
          console.log("");
          outputCoin(false, ambResult.trend);
          console.log(
            `\n\x1b[2mUse \`zora get creator-coin ${parsed.name}\` or \`zora get trend ${parsed.name}\` for a specific type.\x1b[0m`,
          );
        }

        track("cli_get", {
          lookup_type: "name",
          found: true,
          ambiguous: true,
          output_format: json ? "json" : "text",
        });
        return;
      }

      outputCoin(json, ambResult.coin);

      track("cli_get", {
        lookup_type: "name",
        found: true,
        coin_type: ambResult.coin.coinType,
        output_format: json ? "json" : "text",
      });
      return;
    }

    const ref = coinArgsToRef(parsed);

    let result;
    try {
      result = await resolveCoin(ref);
    } catch (err) {
      outputErrorAndExit(json, `Request failed: ${apiErrorMessage(err)}`);
      return;
    }

    if (result.kind === "not-found") {
      outputErrorAndExit(json, result.message);
      return;
    }

    outputCoin(json, result.coin);

    track("cli_get", {
      lookup_type: typeOrId.startsWith("0x") ? "address" : "name",
      coin_type_filter: parsed.kind === "typed" ? parsed.type : null,
      found: true,
      coin_type: result.coin.coinType,
      output_format: json ? "json" : "text",
    });
  });
