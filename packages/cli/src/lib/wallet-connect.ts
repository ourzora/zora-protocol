import { type Address, isAddress } from "viem";
import {
  NoSmartWalletFoundError,
  NotSmartWalletOwnerError,
  SmartWalletNotDeployedError,
  resolveConnection,
} from "./account/connect.js";
import { confirmAgentWalletOverwrite } from "./agent-guard.js";
import { createPublicClient } from "./client/public.js";
import {
  getPrivateKey,
  getWalletPath,
  peekAgentWallet,
  saveConnectedWallet,
} from "./config.js";
import { formatError } from "./errors.js";
import { outputErrorAndExit } from "./output.js";
import { confirmOrDefault, passwordOrFail } from "./prompt.js";
import { SAVE_ERROR_HINT } from "./strings.js";

const isValidPrivateKey = (key: string): boolean =>
  /^(0x)?[0-9a-fA-F]{64}$/.test(key);

const INVALID_KEY_HINT =
  "Must be 64 hex characters, with or without a 0x prefix.";

export interface WalletConnectOptions {
  json: boolean;
  nonInteractive: boolean;
  /** Private key to connect (from positional arg or --key). Prompted if absent. */
  key?: string;
  /** Smart wallet (account) address override, bypassing auto-discovery. */
  smartWallet?: string;
  /** Overwrite an already-configured (non-agent) wallet without prompting. */
  force?: boolean;
}

export interface WalletConnectResult {
  ownerAddress: Address;
  smartWalletAddress: Address;
  /** true when the smart wallet was auto-discovered; false when supplied. */
  discovered: boolean;
  path: string;
}

/**
 * Connects the CLI to an EXISTING Zora account: takes the private key that
 * controls it, discovers (or verifies) the account's smart wallet, and saves both
 * to `wallet.json` so the trading/posting commands act as that account.
 *
 * Mirrors {@link import("./wallet-setup.js").configureWallet}'s overwrite handling:
 * a wallet that owns an agent is guarded irreversibly; a plain wallet just
 * confirms (or requires `--force` when non-interactive).
 */
export async function connectWallet(
  opts: WalletConnectOptions,
): Promise<WalletConnectResult> {
  const { json, nonInteractive } = opts;

  // The active key/account is taken from the environment when set, so a saved
  // wallet would be ignored at runtime — warn rather than silently no-op.
  if (process.env.ZORA_PRIVATE_KEY) {
    console.error(
      "⚠ ZORA_PRIVATE_KEY is set and overrides the saved wallet. Unset it for this connection to take effect.",
    );
  }

  // ── Overwrite guard ─────────────────────────────────────────────────
  const agent = peekAgentWallet();
  if (agent) {
    await confirmAgentWalletOverwrite({ json, nonInteractive, agent });
  } else if (!opts.force) {
    let existing: string | undefined;
    try {
      existing = getPrivateKey();
    } catch (err) {
      return outputErrorAndExit(
        json,
        `✗ Could not read the existing wallet: ${formatError(err)}`,
        "Re-run with --force to overwrite it.",
      );
    }
    if (existing) {
      if (nonInteractive) {
        return outputErrorAndExit(
          json,
          "A wallet is already configured.",
          "Re-run with --force to overwrite it, or without --yes/--json to confirm.",
        );
      }
      const overwrite = await confirmOrDefault(
        {
          message: "A wallet is already configured. Overwrite it?",
          default: false,
        },
        false,
      );
      if (!overwrite) {
        return outputErrorAndExit(
          json,
          "A wallet is already configured.",
          "Re-run with --force to overwrite it.",
        );
      }
    }
  }

  // ── Resolve the private key (arg, then prompt) ──────────────────────
  let key = opts.key?.trim();
  if (key && !isValidPrivateKey(key)) {
    return outputErrorAndExit(
      json,
      "✗ Not a valid private key.",
      INVALID_KEY_HINT,
    );
  }
  while (!key) {
    const input = await passwordOrFail(
      json,
      { message: "Paste the private key that controls your Zora account:" },
      nonInteractive,
    );
    if (isValidPrivateKey(input.trim())) {
      key = input.trim();
    } else {
      console.error(`✗ Not a valid private key. ${INVALID_KEY_HINT}\n`);
    }
  }

  // ── Validate the optional smart-wallet override ─────────────────────
  let smartWalletOverride: Address | undefined;
  if (opts.smartWallet) {
    if (!isAddress(opts.smartWallet)) {
      return outputErrorAndExit(
        json,
        `✗ Invalid --smart-wallet address: ${opts.smartWallet}`,
      );
    }
    smartWalletOverride = opts.smartWallet;
  }

  // ── Discover / verify the account's smart wallet on-chain ───────────
  const client = createPublicClient();
  let resolution;
  try {
    resolution = await resolveConnection({
      privateKey: key,
      client,
      smartWalletOverride,
    });
  } catch (err) {
    if (err instanceof NoSmartWalletFoundError) {
      return outputErrorAndExit(
        json,
        `✗ Couldn't find a deployed Zora smart wallet for ${err.ownerAddress}.`,
        "If you know the address, pass --smart-wallet <addr>. The key may not control a Zora account, or its smart wallet isn't deployed yet.",
      );
    }
    if (err instanceof SmartWalletNotDeployedError) {
      return outputErrorAndExit(
        json,
        `✗ Smart wallet ${err.smartWalletAddress} is not deployed on Base.`,
        "Pass the address of a deployed Zora smart wallet.",
      );
    }
    if (err instanceof NotSmartWalletOwnerError) {
      return outputErrorAndExit(
        json,
        `✗ ${err.ownerAddress} is not an owner of smart wallet ${err.smartWalletAddress}.`,
        "Connect with the private key that controls that account.",
      );
    }
    return outputErrorAndExit(json, `✗ Failed to connect: ${formatError(err)}`);
  }

  // ── Persist ─────────────────────────────────────────────────────────
  try {
    saveConnectedWallet(key, resolution.smartWalletAddress);
  } catch {
    return outputErrorAndExit(
      json,
      `✗ Couldn't save to ${getWalletPath()}.`,
      SAVE_ERROR_HINT,
    );
  }

  return {
    ownerAddress: resolution.ownerAddress,
    smartWalletAddress: resolution.smartWalletAddress,
    discovered: resolution.discovered,
    path: getWalletPath(),
  };
}
