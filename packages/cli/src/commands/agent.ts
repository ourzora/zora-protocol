import { Command } from "commander";
import { generatePrivateKey } from "viem/accounts";
import { getPrivateKey, savePrivateKey, getWalletPath } from "../lib/config.js";
import { getJson, outputData, outputErrorAndExit } from "../lib/output.js";
import { track } from "../lib/analytics.js";
import { formatError } from "../lib/errors.js";
import {
  ZORA_PRIVY_APP_ID,
  DEFAULT_SIWE_ORIGIN,
  DEFAULT_SIWE_CHAIN_ID,
} from "../lib/privy.js";
import { onboardAgent } from "../lib/agent/onboard.js";

const PRIVATE_KEY_RE = /^(0x)?[0-9a-fA-F]{64}$/;
const normalizeKey = (key: string): `0x${string}` =>
  (key.startsWith("0x") ? key : `0x${key}`) as `0x${string}`;

interface ResolvedKey {
  key: `0x${string}`;
  source: string;
  generated: boolean;
}

/**
 * Resolve the agent EOA, in priority order:
 *   1. --private-key flag
 *   2. ZORA_PRIVATE_KEY env var
 *   3. the saved CLI wallet (wallet.json)
 *   4. generate a fresh key and persist it
 */
function resolveAgentKey(
  json: boolean,
  override: string | undefined,
): ResolvedKey {
  if (override !== undefined) {
    if (!PRIVATE_KEY_RE.test(override.trim())) {
      return outputErrorAndExit(
        json,
        "--private-key isn't a valid private key.",
      );
    }
    // Warn (to stderr, so JSON output on stdout is unaffected): a key passed on
    // the command line is exposed in shell history and process listings.
    console.error(
      "⚠ Passing --private-key exposes it in shell history and process listings. Prefer ZORA_PRIVATE_KEY or the saved wallet file.",
    );
    return {
      key: normalizeKey(override.trim()),
      source: "--private-key",
      generated: false,
    };
  }

  const envKey = process.env.ZORA_PRIVATE_KEY;
  if (envKey) {
    if (!PRIVATE_KEY_RE.test(envKey.trim())) {
      return outputErrorAndExit(
        json,
        "ZORA_PRIVATE_KEY isn't a valid private key.",
      );
    }
    return {
      key: normalizeKey(envKey.trim()),
      source: "env (ZORA_PRIVATE_KEY)",
      generated: false,
    };
  }

  let stored: string | undefined;
  try {
    stored = getPrivateKey();
  } catch (err) {
    return outputErrorAndExit(
      json,
      `Could not read your wallet: ${formatError(err)}`,
      "Fix or delete the wallet file, or pass --private-key.",
    );
  }
  if (stored) {
    if (!PRIVATE_KEY_RE.test(stored.trim())) {
      return outputErrorAndExit(
        json,
        `Your saved wallet (${getWalletPath()}) appears corrupted — its key isn't a valid private key.`,
        "Fix or delete the wallet file, or pass --private-key.",
      );
    }
    return {
      key: normalizeKey(stored.trim()),
      source: getWalletPath(),
      generated: false,
    };
  }

  const generated = generatePrivateKey();
  try {
    savePrivateKey(generated);
  } catch (err) {
    return outputErrorAndExit(
      json,
      `Could not save the generated wallet: ${formatError(err)}`,
    );
  }
  return { key: generated, source: getWalletPath(), generated: true };
}

export const agentCommand = new Command("agent")
  .description(
    "Create and manage a Zora agent identity.\nStands up an identity from an EOA — a headless Privy account, a Zora profile, and a smart wallet — with no human interaction.",
  )
  .action(function (this: Command) {
    this.outputHelp();
  });

agentCommand
  .command("create")
  .description(
    "Create a Zora agent from an EOA, unattended: a headless Privy account (Sign-In-With-Ethereum), a Zora profile, and a sponsored smart wallet. Prints a Privy access token for further Zora API calls.",
  )
  .option(
    "--private-key <key>",
    "EOA private key to sign in with (default: ZORA_PRIVATE_KEY, then your saved wallet, else a new one is generated)",
  )
  .option("--app-id <id>", "Privy app id", ZORA_PRIVY_APP_ID)
  .option("--origin <url>", "SIWE origin", DEFAULT_SIWE_ORIGIN)
  .option(
    "--chain-id <id>",
    "EVM chain id for SIWE",
    String(DEFAULT_SIWE_CHAIN_ID),
  )
  .option("--rpc-url <url>", "Base RPC URL (defaults to the public endpoint)")
  .action(async function (
    this: Command,
    options: {
      privateKey?: string;
      appId: string;
      origin: string;
      chainId: string;
      rpcUrl?: string;
    },
  ) {
    const json = getJson(this);

    const chainId = Number(options.chainId);
    if (!Number.isInteger(chainId) || chainId <= 0) {
      return outputErrorAndExit(json, `Invalid --chain-id: ${options.chainId}`);
    }

    const resolved = resolveAgentKey(json, options.privateKey);

    let result;
    try {
      result = await onboardAgent({
        privateKey: resolved.key,
        appId: options.appId,
        origin: options.origin,
        chainId,
        rpcUrl: options.rpcUrl,
        onProgress: json
          ? undefined
          : (_step, detail) => console.log(`• ${detail} ...`),
      });
    } catch (err) {
      return outputErrorAndExit(
        json,
        `Agent onboarding failed: ${formatError(err)}`,
        "Re-run to retry — the profile and smart wallet are idempotent.",
      );
    }

    track("cli_agent_create", {
      is_new_user: result.isNewUser,
      generated_wallet: resolved.generated,
      output_format: json ? "json" : "text",
    });

    outputData(json, {
      json: { ...result, walletSource: resolved.source },
      render: () => {
        console.log("\n✓ Agent ready");
        console.log(
          `  Profile:      @${result.username}  (https://zora.co/@${result.username})`,
        );
        console.log(`  Wallet (EOA): ${result.address}`);
        console.log(`  Smart wallet: ${result.smartWallet}`);
        console.log(`  Privy DID:    ${result.did}`);
        if (resolved.generated) {
          console.log(
            `\n  A new wallet was generated and saved to ${resolved.source}. Back it up — it owns this agent.`,
          );
        }
        console.log("\n  Access token (Authorization: Bearer, ~1h):");
        console.log(`  ${result.accessToken}`);
      },
    });
  });
