import { Command } from "commander";
import { readFileSync } from "node:fs";
import { basename, extname } from "node:path";
import { generatePrivateKey } from "viem/accounts";
import {
  getPrivateKey,
  savePrivateKey,
  saveAgentWallet,
  getWalletPath,
} from "../lib/config.js";
import { getJson, outputData, outputErrorAndExit } from "../lib/output.js";
import { track } from "../lib/analytics.js";
import { formatError } from "../lib/errors.js";
import {
  ZORA_PRIVY_APP_ID,
  DEFAULT_SIWE_ORIGIN,
  DEFAULT_SIWE_CHAIN_ID,
  createPrivyAccount,
} from "../lib/privy.js";
import { onboardAgent } from "../lib/agent/onboard.js";
import { updateAgentProfile } from "../lib/agent/update-profile.js";
import { ipfsUpload } from "../lib/agent/zora-client.js";

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
 *   4. generate a fresh key and persist it (only when `allowGenerate`)
 *
 * `allowGenerate` is false for commands that act on an existing agent (e.g.
 * `update`): minting a fresh wallet there would point at a different, empty
 * identity, so we error out instead.
 */
function resolveAgentKey(
  json: boolean,
  override: string | undefined,
  { allowGenerate = true }: { allowGenerate?: boolean } = {},
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

  if (!allowGenerate) {
    return outputErrorAndExit(
      json,
      "No agent wallet found.",
      "Pass --private-key, set ZORA_PRIVATE_KEY, or run `zora agent create` first.",
    );
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

const AVATAR_MIME_BY_EXT: Record<string, string> = {
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".gif": "image/gif",
  ".webp": "image/webp",
};

/** Read a local image and upload it to IPFS, returning its `ipfs://` URI. */
async function uploadAvatar(token: string, path: string): Promise<string> {
  const mime = AVATAR_MIME_BY_EXT[extname(path).toLowerCase()];
  if (!mime) {
    throw new Error(
      `Unsupported avatar image "${path}". Use a PNG, JPG, GIF, or WebP file.`,
    );
  }
  const bytes = new Uint8Array(readFileSync(path));
  return ipfsUpload(token, basename(path), bytes, mime);
}

export const agentCommand = new Command("agent")
  .description(
    "Create and manage a Zora agent identity.\nStands up a full identity from an EOA — Privy account, profile, smart wallet, coin, and first post — with no human interaction.",
  )
  .action(function (this: Command) {
    this.outputHelp();
  });

agentCommand
  .command("create")
  .description(
    "Create a complete Zora agent from an EOA, end to end and unattended: headless Privy account, profile, smart wallet, creator coin, and a first post. Every on-chain step is sponsored, so the agent needs no ETH.",
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
  .option(
    "--dry-run",
    "Create the account, profile, and smart wallet, but simulate the coin + post instead of minting them",
  )
  .option("--skip-coin", "Skip creating the creator coin")
  .option("--skip-post", "Skip publishing the first post")
  .action(async function (
    this: Command,
    options: {
      privateKey?: string;
      appId: string;
      origin: string;
      chainId: string;
      rpcUrl?: string;
      dryRun?: boolean;
      skipCoin?: boolean;
      skipPost?: boolean;
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
        dryRun: Boolean(options.dryRun),
        skipCoin: Boolean(options.skipCoin),
        skipPost: Boolean(options.skipPost),
        onProgress: json
          ? undefined
          : (_step, detail) => console.log(`• ${detail} ...`),
      });
    } catch (err) {
      return outputErrorAndExit(
        json,
        `Agent onboarding failed: ${formatError(err)}`,
        "Re-run to retry — the profile and smart wallet are idempotent. Use --skip-coin / --skip-post to resume past a completed step.",
      );
    }

    // Persist the agent's full identity (EOA, embedded + smart wallet, Privy DID,
    // and profile) to the wallet file so it can be recovered later. We only write
    // when the wallet file is the home of this key — it was generated or already
    // stored there — so we never persist a key supplied via --private-key or
    // ZORA_PRIVATE_KEY, nor clobber an unrelated saved wallet. The smart + embedded
    // wallets are real even under --dry-run, so we persist regardless. The agent
    // already exists on-chain here, so a write failure is a warning, not a hard error.
    const walletPath = getWalletPath();
    let savedToWallet = false;
    if (resolved.source === walletPath) {
      try {
        saveAgentWallet({
          address: result.address,
          embeddedWalletAddress: result.embedded,
          smartWalletAddress: result.smartWallet,
          did: result.did,
          username: result.username,
          profileUrl: result.profileUrl,
          createdAt: new Date().toISOString(),
        });
        savedToWallet = true;
      } catch (err) {
        console.error(
          `⚠ Created the agent but couldn't save its details to ${walletPath}: ${formatError(err)}`,
        );
      }
    }

    track("cli_agent_create", {
      is_new_user: result.isNewUser,
      generated_wallet: resolved.generated,
      saved_to_wallet: savedToWallet,
      dry_run: result.dryRun,
      minted_coin: Boolean(result.coin?.hash),
      minted_post: Boolean(result.post?.hash),
      output_format: json ? "json" : "text",
    });

    outputData(json, {
      json: {
        ...result,
        walletSource: resolved.source,
        walletPath,
        savedToWallet,
      },
      render: () => {
        console.log(
          result.dryRun
            ? "\n✓ Agent ready (dry run — coin + post simulated, not minted)"
            : "\n✓ Agent ready",
        );
        console.log(`  Profile:      @${result.username}`);
        console.log(`  Wallet (EOA): ${result.address}`);
        console.log(`  Smart wallet: ${result.smartWallet}`);
        console.log(`  Privy DID:    ${result.did}`);
        if (result.coin) {
          console.log(
            `  Creator coin: ${
              result.dryRun
                ? "simulated ✓"
                : result.coin.hash
                  ? `minted — tx ${result.coin.hash}`
                  : "—"
            }`,
          );
        }
        if (result.post) {
          console.log(
            `  First post:   "${result.post.greeting}"${
              result.dryRun
                ? " (simulated ✓)"
                : result.post.hash
                  ? ` — minted, tx ${result.post.hash}`
                  : ""
            }`,
          );
        }
        console.log("\n  Links:");
        console.log(`    Profile:      ${result.profileUrl}`);
        if (result.coin?.url) {
          console.log(`    Creator coin: ${result.coin.url}`);
        }
        if (result.post?.url) {
          console.log(`    First post:   ${result.post.url}`);
        }
        if (resolved.generated) {
          console.log(
            `\n  A new wallet was generated and saved to ${walletPath}. Back it up — it owns this agent.`,
          );
        }
        if (savedToWallet) {
          console.log(
            `${resolved.generated ? "" : "\n"}  Agent identity saved to ${walletPath} — EOA, embedded + smart wallet, Privy DID, and profile.`,
          );
        }
        console.log("\n  Access token (Authorization: Bearer, ~1h):");
        console.log(`  ${result.accessToken}`);
      },
    });
  });

agentCommand
  .command("update")
  .description(
    "Update an existing agent's profile — username, bio, and/or avatar. Signs in with the agent's EOA (its Privy account) and edits that agent's Zora profile.",
  )
  .option(
    "--private-key <key>",
    "EOA private key to sign in with (default: ZORA_PRIVATE_KEY, then your saved wallet)",
  )
  .option("--username <name>", "New username (also updates the display name)")
  .option("--bio <text>", 'New bio (pass "" to clear it)')
  .option(
    "--avatar <path>",
    "Path to a local image (PNG/JPG/GIF/WebP) to upload as the new avatar",
  )
  .option("--app-id <id>", "Privy app id", ZORA_PRIVY_APP_ID)
  .option("--origin <url>", "SIWE origin", DEFAULT_SIWE_ORIGIN)
  .option(
    "--chain-id <id>",
    "EVM chain id for SIWE",
    String(DEFAULT_SIWE_CHAIN_ID),
  )
  .action(async function (
    this: Command,
    options: {
      privateKey?: string;
      username?: string;
      bio?: string;
      avatar?: string;
      appId: string;
      origin: string;
      chainId: string;
    },
  ) {
    const json = getJson(this);

    // Commander leaves an omitted option `undefined`; an explicit empty value
    // (e.g. `--bio ""`) comes through as "". We forward only provided fields, so
    // omitted = unchanged and "" = clear (server-side), and require at least one.
    if (
      options.username === undefined &&
      options.bio === undefined &&
      options.avatar === undefined
    ) {
      return outputErrorAndExit(
        json,
        "Nothing to update.",
        "Pass at least one of --username, --bio, or --avatar.",
      );
    }

    const chainId = Number(options.chainId);
    if (!Number.isInteger(chainId) || chainId <= 0) {
      return outputErrorAndExit(json, `Invalid --chain-id: ${options.chainId}`);
    }

    const resolved = resolveAgentKey(json, options.privateKey, {
      allowGenerate: false,
    });

    let privy;
    try {
      privy = await createPrivyAccount({
        privateKey: resolved.key,
        appId: options.appId,
        origin: options.origin,
        chainId,
      });
    } catch (err) {
      return outputErrorAndExit(json, `Sign-in failed: ${formatError(err)}`);
    }

    let avatarUri: string | undefined;
    if (options.avatar !== undefined) {
      if (options.avatar === "") {
        // An empty value clears the avatar server-side — nothing to upload.
        avatarUri = "";
      } else {
        try {
          avatarUri = await uploadAvatar(privy.accessToken, options.avatar);
        } catch (err) {
          return outputErrorAndExit(
            json,
            `Avatar upload failed: ${formatError(err)}`,
          );
        }
      }
    }

    let profile;
    try {
      profile = await updateAgentProfile(privy.accessToken, {
        username: options.username,
        bio: options.bio,
        avatarUri,
      });
    } catch (err) {
      return outputErrorAndExit(
        json,
        `Profile update failed: ${formatError(err)}`,
        "Check the new username isn't taken and the EOA owns an agent account.",
      );
    }

    track("cli_agent_update", {
      updated_username: options.username !== undefined,
      updated_bio: options.bio !== undefined,
      updated_avatar: options.avatar !== undefined,
      output_format: json ? "json" : "text",
    });

    const profileUrl = `https://zora.co/@${profile.username}`;
    outputData(json, {
      json: {
        username: profile.username,
        avatarUri: profile.avatarUri,
        profileUrl,
      },
      render: () => {
        console.log("\n✓ Profile updated");
        console.log(`  Profile: @${profile.username}`);
        if (options.bio !== undefined) {
          console.log(
            `  Bio:     ${options.bio === "" ? "(cleared)" : options.bio}`,
          );
        }
        if (options.avatar !== undefined) {
          console.log(
            `  Avatar:  ${options.avatar === "" ? "(cleared)" : profile.avatarUri}`,
          );
        }
        console.log(`\n  Link: ${profileUrl}`);
      },
    });
  });
