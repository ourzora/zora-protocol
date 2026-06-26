import { Command } from "commander";
import confirm from "@inquirer/confirm";
import { generatePrivateKey } from "viem/accounts";
import {
  getPrivateKey,
  savePrivateKey,
  saveAgentWallet,
  getWalletPath,
  peekAgentWallet,
  getBudget,
  saveBudget,
  clearBudget,
  getBudgetPath,
  type BudgetPeriod,
} from "../lib/config.js";
import {
  appendSpend,
  evaluate,
  periodMs,
  usdFromEth,
} from "../lib/agent/budget.js";
import { formatUsd } from "../lib/format.js";
import { safeExit, SUCCESS } from "../lib/exit.js";
import {
  getJson,
  getYes,
  outputData,
  outputErrorAndExit,
} from "../lib/output.js";
import { confirmAgentAction } from "../lib/agent-guard.js";
import { track, setPersonProperties } from "../lib/analytics.js";
import { formatError } from "../lib/errors.js";
import {
  ZORA_PRIVY_APP_ID,
  DEFAULT_SIWE_ORIGIN,
  DEFAULT_SIWE_CHAIN_ID,
  createPrivyAccount,
  sendEmailCode,
  linkEmailWithCode,
  hasLinkedEmail,
} from "../lib/privy.js";
import { inputOrFail } from "../lib/prompt.js";
import { validateTicker } from "../lib/ticker.js";
import { onboardAgent, createAgentCoin } from "../lib/agent/onboard.js";
import { updateAgentProfile } from "../lib/agent/update-profile.js";
import { detectAgentHarness } from "../lib/agent-harness.js";
import {
  loadAvatar,
  loadImageFile,
  uploadAvatar,
  type AvatarFile,
} from "../lib/agent/avatar.js";

const PRIVATE_KEY_RE = /^(0x)?[0-9a-fA-F]{64}$/;
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
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

export const agentCommand = new Command("agent")
  .description(
    "Create and manage a Zora agent identity.\nStands up an identity from an EOA — Privy account, profile, smart wallet, and creator coin — with no human interaction.",
  )
  .action(function (this: Command) {
    this.outputHelp();
  });

agentCommand
  .command("create")
  .description(
    "Create a Zora agent from an EOA, end to end and unattended: headless Privy account, profile, smart wallet, and creator coin. A first post is published when --caption and --image are supplied. Every on-chain step is sponsored, so the agent needs no ETH. Skip the coin with --skip-coin.",
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
  .option("--skip-coin", "Skip minting the agent's creator coin")
  .option("--skip-post", "Skip publishing the first post")
  .option(
    "--username <name>",
    "Set the agent's username (also sets the display name; must be available). Default: an auto-assigned handle.",
  )
  .option("--bio <text>", "Set the agent's bio. Default: an auto-assigned bio.")
  .option(
    "--avatar <path>",
    "Set the agent's avatar from a local image (PNG/JPG/GIF/WebP). Default: an auto-assigned avatar.",
  )
  .option(
    "--caption <text>",
    "First-post meme caption, rendered as the big centered text on the card. Required (with --image) to publish a first post.",
  )
  .option(
    "--image <path>",
    "First-post background photo from a local image (PNG/JPG/GIF/WebP). Required (with --caption) to publish a first post.",
  )
  .option("--title <text>", "First-post coin name. Default: the caption.")
  .option(
    "--ticker <symbol>",
    "First-post coin ticker (2–20 letters/numbers). Required to publish a first post.",
  )
  .option(
    "--description <text>",
    "First-post coin description. Default: the caption.",
  )
  .option(
    "--force",
    "Proceed even if an agent already exists on this wallet, without confirming",
  )
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
      username?: string;
      bio?: string;
      avatar?: string;
      caption?: string;
      image?: string;
      title?: string;
      ticker?: string;
      description?: string;
      force?: boolean;
    },
  ) {
    const json = getJson(this);

    const chainId = Number(options.chainId);
    if (!Number.isInteger(chainId) || chainId <= 0) {
      return outputErrorAndExit(json, `Invalid --chain-id: ${options.chainId}`);
    }

    // An explicit empty handle is rejected server-side; catch it up front with a
    // clearer message. (`--bio ""` is allowed — it clears the auto-assigned bio.)
    if (options.username !== undefined && options.username.trim() === "") {
      return outputErrorAndExit(
        json,
        "--username can't be empty.",
        "Pass a handle, or omit --username to get an auto-assigned one.",
      );
    }

    // Read + validate the avatar before any on-chain work, so a bad image fails
    // fast rather than after a real agent identity has been minted. The upload
    // itself happens inside onboardAgent, once it holds the Privy session token.
    let avatar: AvatarFile | undefined;
    if (options.avatar !== undefined) {
      try {
        avatar = loadAvatar(options.avatar);
      } catch (err) {
        return outputErrorAndExit(json, formatError(err));
      }
    }

    // A custom first-post ticker is forced as-is, so reject an invalid one up
    // front (before any on-chain work) rather than letting it fail mid-mint.
    if (options.ticker !== undefined) {
      const tickerError = validateTicker(options.ticker);
      if (tickerError) {
        return outputErrorAndExit(json, tickerError, "Pass a valid --ticker.");
      }
    }

    // The first post needs both a caption and a background image. Require them
    // together: passing only one is a mistake (an incomplete card), and passing
    // neither simply skips the post. Validate + read the image up front, for the
    // same fail-fast reason as the avatar above.
    const hasCaption = Boolean(options.caption && options.caption.trim());
    const hasImage = options.image !== undefined;
    if (hasCaption !== hasImage && !options.skipPost) {
      return outputErrorAndExit(
        json,
        "To publish a first post, pass both --caption and --image.",
        "Pass both, or omit both to skip the first post.",
      );
    }

    // A first post must have an explicit ticker — we don't silently auto-derive
    // one for the published coin. Require --ticker whenever a post will be minted
    // (both caption + image present and the post isn't skipped).
    const willPost = hasCaption && hasImage && !options.skipPost;
    if (willPost && options.ticker === undefined) {
      return outputErrorAndExit(
        json,
        "Publishing a first post requires a --ticker.",
        "Pass --ticker <symbol> (2–20 letters/numbers), or omit --caption/--image to skip the post.",
      );
    }
    let postImage: AvatarFile | undefined;
    if (hasImage) {
      try {
        postImage = loadImageFile(options.image!, "Post image");
      } catch (err) {
        return outputErrorAndExit(json, formatError(err));
      }
    }

    const resolved = resolveAgentKey(json, options.privateKey);

    // Re-running create on a wallet that already owns an agent re-mints
    // the creator coin (unless --skip-coin) and/or another first post
    // (--caption + --image). Only confirm when this run would actually mint
    // something — a bare re-run just re-resolves the idempotent account.
    // --dry-run mints nothing, so skip it there too.
    const wouldMint = !options.skipCoin || (hasCaption && hasImage);
    if (!options.dryRun && wouldMint) {
      const existingAgent = peekAgentWallet();
      if (existingAgent) {
        await confirmAgentAction({
          json,
          force: options.force,
          warning: (() => {
            const willMintCoin = !options.skipCoin;
            const willMintPost = hasCaption && hasImage;
            const what = [
              willMintCoin && "creator coin",
              willMintPost && "first post",
            ]
              .filter(Boolean)
              .join(" and ");
            return (
              `You already have an agent: @${existingAgent.username} (smart wallet ${existingAgent.smartWalletAddress}).\n` +
              `Re-running 'agent create' will mint another ${what} for it.`
            );
          })(),
          question: (() => {
            const willMintCoin = !options.skipCoin;
            const willMintPost = hasCaption && hasImage;
            const what = [willMintCoin && "coin", willMintPost && "post"]
              .filter(Boolean)
              .join("/");
            return `Create another ${what} for @${existingAgent.username}?`;
          })(),
        });
      }
    }

    let result;
    try {
      result = await onboardAgent({
        privateKey: resolved.key,
        appId: options.appId,
        origin: options.origin,
        chainId,
        agentHarness: detectAgentHarness(process.cwd()),
        rpcUrl: options.rpcUrl,
        dryRun: Boolean(options.dryRun),
        skipCoin: Boolean(options.skipCoin),
        skipPost: Boolean(options.skipPost),
        username: options.username,
        bio: options.bio,
        avatar,
        caption: options.caption,
        postImage,
        postTitle: options.title,
        postTicker: options.ticker,
        postDescription: options.description,
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
      skip_coin: Boolean(options.skipCoin),
      minted_coin: Boolean(result.coin?.hash),
      minted_post: Boolean(result.post?.hash),
      coin_failed: Boolean(result.coinError),
      post_failed: Boolean(result.postError),
      set_username: options.username !== undefined,
      set_bio: options.bio !== undefined,
      set_avatar: options.avatar !== undefined,
      set_caption: hasCaption,
      set_image: hasImage,
      set_ticker: options.ticker !== undefined,
      output_format: json ? "json" : "text",
    });

    // Persist the agent's username as the `name` person property in PostHog so
    // the profile is identifiable beyond the wallet/api-key hash.
    setPersonProperties({ name: result.username });

    outputData(json, {
      json: {
        ...result,
        // `bio` isn't echoed back by the profile mutation, so surface the value
        // that was applied (omitted from JSON when --bio wasn't passed).
        bio: options.bio,
        walletSource: resolved.source,
        walletPath,
        savedToWallet,
      },
      render: () => {
        const simulated = result.dryRun && (result.coin || result.post);
        const simulatedWhat = [result.coin && "coin", result.post && "post"]
          .filter(Boolean)
          .join(" + ");
        console.log(
          simulated
            ? `\n✓ Agent ready (dry run — ${simulatedWhat} simulated, not minted)`
            : result.dryRun
              ? "\n✓ Agent ready (dry run — account + smart wallet created; coin + post skipped)"
              : "\n✓ Agent ready",
        );
        console.log(`  Profile:      @${result.username}`);
        if (options.bio !== undefined) {
          console.log(
            `  Bio:          ${options.bio === "" ? "(none)" : options.bio}`,
          );
        }
        if (options.avatar !== undefined && result.avatarUri) {
          console.log(`  Avatar:       ${result.avatarUri}`);
        }
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
        } else if (result.coinError) {
          console.log(`  Creator coin: failed — ${result.coinError}`);
          console.log("  Retry with `zora agent coin`.");
        } else if (!result.dryRun && options.skipCoin) {
          console.log(
            "  Creator coin: skipped — add one later with `zora agent coin`",
          );
        }
        if (result.post) {
          console.log(
            `  First post:   "${result.post.caption}"${
              result.dryRun
                ? " (simulated ✓)"
                : result.post.hash
                  ? ` — minted, tx ${result.post.hash}`
                  : ""
            }`,
          );
        } else if (result.postError) {
          console.log(`  First post:   failed — ${result.postError}`);
        }
        console.log("\n  Links:");
        console.log(`    Profile:      ${result.profileUrl}`);
        if (result.coin?.url) {
          console.log(`    Creator coin: ${result.coin.url}`);
        }
        if (result.post?.url) {
          // The post link falls back to the profile URL when the content-coin
          // address couldn't be resolved; flag that so the duplicate isn't
          // mistaken for the precise post link.
          const note = result.post.coinAddress
            ? ""
            : "  (first post — shown on the profile; coin still indexing)";
          console.log(`    First post:   ${result.post.url}${note}`);
        }
        if (result.coinError || result.postError) {
          console.log(
            "\n  Note: the account was created, but a best-effort step did not complete.",
          );
          if (result.coinError) {
            console.log("  Create the coin later with `zora agent coin`.");
          }
          if (result.postError) {
            console.log(
              "  Re-run with --caption / --image to retry the first post.",
            );
          }
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
  .command("coin")
  .description(
    "Create the agent's creator coin for an existing agent. Signs in with the agent's EOA (reusing its cached Privy session), then mints the sponsored creator coin — its name and ticker come from the profile. Needs no ETH. Use this when `agent create` was run with --skip-coin.",
  )
  .option(
    "--private-key <key>",
    "EOA private key to sign in with (default: ZORA_PRIVATE_KEY, then your saved wallet)",
  )
  .option("--app-id <id>", "Privy app id", ZORA_PRIVY_APP_ID)
  .option("--origin <url>", "SIWE origin", DEFAULT_SIWE_ORIGIN)
  .option(
    "--chain-id <id>",
    "EVM chain id for SIWE",
    String(DEFAULT_SIWE_CHAIN_ID),
  )
  .option("--rpc-url <url>", "Base RPC URL (defaults to the public endpoint)")
  .option("--dry-run", "Simulate the creator coin instead of minting it")
  .option(
    "--force",
    "Skip the confirmation before minting (e.g. to deliberately mint another coin)",
  )
  .action(async function (
    this: Command,
    options: {
      privateKey?: string;
      appId: string;
      origin: string;
      chainId: string;
      rpcUrl?: string;
      dryRun?: boolean;
      force?: boolean;
    },
  ) {
    const json = getJson(this);

    const chainId = Number(options.chainId);
    if (!Number.isInteger(chainId) || chainId <= 0) {
      return outputErrorAndExit(json, `Invalid --chain-id: ${options.chainId}`);
    }

    // Acts on an existing agent — don't generate a fresh wallet (that would point
    // at a different, empty identity with no profile to attach a coin to).
    const resolved = resolveAgentKey(json, options.privateKey, {
      allowGenerate: false,
    });

    // Minting a creator coin is an irreversible on-chain action, and running this
    // again mints ANOTHER coin. Confirm first when the wallet already owns an agent
    // (parity with `agent create`, which mints by default). --dry-run mints nothing,
    // so skip it there; --json (scripted) and --force proceed without prompting.
    if (!options.dryRun) {
      const existingAgent = peekAgentWallet();
      if (existingAgent) {
        await confirmAgentAction({
          json,
          force: options.force,
          warning:
            `Minting a creator coin for @${existingAgent.username} (smart wallet ${existingAgent.smartWalletAddress}).\n` +
            `Running 'agent coin' again will mint ANOTHER creator coin.`,
          question: `Mint the creator coin for @${existingAgent.username}?`,
        });
      }
    }

    let result;
    try {
      result = await createAgentCoin({
        privateKey: resolved.key,
        appId: options.appId,
        origin: options.origin,
        chainId,
        rpcUrl: options.rpcUrl,
        dryRun: Boolean(options.dryRun),
        onProgress: json
          ? undefined
          : (_step, detail) => console.log(`• ${detail} ...`),
      });
    } catch (err) {
      return outputErrorAndExit(
        json,
        `Creating the creator coin failed: ${formatError(err)}`,
        "Run `zora agent create` first if this EOA has no agent yet; otherwise re-run to retry.",
      );
    }

    track("cli_agent_coin", {
      dry_run: result.dryRun,
      minted_coin: Boolean(result.coin.hash),
      output_format: json ? "json" : "text",
    });

    outputData(json, {
      json: { ...result, walletSource: resolved.source },
      render: () => {
        console.log(
          result.dryRun
            ? "\n✓ Creator coin simulated (dry run — not minted)"
            : "\n✓ Creator coin created",
        );
        console.log(`  Profile:      @${result.username}`);
        console.log(`  Wallet (EOA): ${result.address}`);
        console.log(
          `  Creator coin: ${
            result.dryRun
              ? "simulated ✓"
              : result.coin.hash
                ? `minted — tx ${result.coin.hash}`
                : "—"
          }`,
        );
        console.log("\n  Links:");
        console.log(`    Profile:      ${result.profileUrl}`);
        if (result.coin.url) {
          console.log(`    Creator coin: ${result.coin.url}`);
        }
        console.log("\n  Access token (Authorization: Bearer, ~1h):");
        console.log(`  ${result.accessToken}`);
      },
    });
  });

agentCommand
  .command("connect-email")
  .description(
    "Link an email to your agent's Privy account via an emailed one-time code. " +
      "Signs in with your EOA (Sign-In-With-Ethereum), sends a code to the email, " +
      "and attaches it to the account once you enter the code.",
  )
  .option("--email <addr>", "Email to link (prompted if omitted)")
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
  .option(
    "--code <code>",
    "One-time code from the linking email. Pass it to finish linking without a prompt; omit it to send a fresh code.",
  )
  .option(
    "--yes",
    "Skip interactive prompts. Without --code the code is sent and the command exits so you can re-run with --code <code>.",
  )
  .action(async function (
    this: Command,
    options: {
      email?: string;
      code?: string;
      privateKey?: string;
      appId: string;
      origin: string;
      chainId: string;
      yes?: boolean;
    },
  ) {
    const json = getJson(this);
    const nonInteractive = getYes(this);
    // The emailed code can't be prompted for in JSON or --yes mode. In that
    // case the flow is split across two runs: one to send the code, one with
    // --code to finish linking.
    const canPrompt = !json && !nonInteractive;
    const code = options.code?.trim();

    const chainId = Number(options.chainId);
    if (!Number.isInteger(chainId) || chainId <= 0) {
      return outputErrorAndExit(json, `Invalid --chain-id: ${options.chainId}`);
    }

    // Validate a passed --email before doing any network work.
    let email = options.email?.trim();
    if (email !== undefined && !EMAIL_RE.test(email)) {
      return outputErrorAndExit(
        json,
        `--email isn't a valid email address: ${options.email}`,
      );
    }

    const resolved = resolveAgentKey(json, options.privateKey);

    // 1. Sign in to Privy with the EOA (reuses the saved wallet) to get a session.
    let account;
    try {
      account = await createPrivyAccount({
        privateKey: resolved.key,
        appId: options.appId,
        origin: options.origin,
        chainId,
      });
    } catch (err) {
      return outputErrorAndExit(
        json,
        `Could not sign in to Privy with your wallet: ${formatError(err)}`,
        "Check your network connection and try again.",
      );
    }

    // 2. The target email is needed before the already-linked check and the
    //    send, so prompt for it now if it wasn't passed.
    if (!email) {
      email = (
        await inputOrFail(json, { message: "Email to link:" }, !canPrompt)
      ).trim();
      if (!EMAIL_RE.test(email)) {
        return outputErrorAndExit(json, "That isn't a valid email address.");
      }
    }

    // 3. Already linked? Nothing to send.
    if (hasLinkedEmail(account.linkedAccounts, email)) {
      track("cli_agent_connect_email", {
        already_linked: true,
        generated_wallet: resolved.generated,
        output_format: json ? "json" : "text",
      });
      setPersonProperties({ email });
      return outputData(json, {
        json: {
          email,
          did: account.did,
          address: account.address,
          alreadyLinked: true,
          linkedAccounts: account.linkedAccounts,
          walletSource: resolved.source,
        },
        render: () => {
          console.log(`\n✓ ${email} is already linked to this account.`);
          console.log(`  Privy DID: ${account.did}`);
        },
      });
    }

    // 4. Resolve the one-time code. If --code was passed, use it directly and
    //    skip sending a fresh one; the operator already received it from a
    //    prior run. Otherwise send a code now.
    let codeToVerify = code;
    if (!codeToVerify) {
      try {
        await sendEmailCode({
          accessToken: account.accessToken,
          email,
          appId: options.appId,
          origin: options.origin,
          cookie: account.cookie,
        });
      } catch (err) {
        return outputErrorAndExit(
          json,
          `Could not send a code to ${email}: ${formatError(err)}`,
          "Check the address and try again in a moment.",
        );
      }

      // Non-interactive (JSON or --yes): we can't prompt for the emailed code,
      // so stop here and let the operator re-run with --code to finish linking.
      if (!canPrompt) {
        track("cli_agent_connect_email", {
          code_sent: true,
          already_linked: false,
          generated_wallet: resolved.generated,
          output_format: json ? "json" : "text",
        });
        // Mirror whichever non-interactive flag the caller used so the
        // suggested follow-up command matches how they're driving the CLI.
        const nextStep = `zora agent connect-email --email ${email} --code <code> ${json ? "--json" : "--yes"}`;
        return outputData(json, {
          json: {
            email,
            did: account.did,
            address: account.address,
            codeSent: true,
            alreadyLinked: false,
            walletSource: resolved.source,
            // Make the response self-describing for non-interactive agents:
            // tell them the flow isn't done and exactly how to finish it.
            status: "awaiting_code",
            message: `A one-time code was emailed to ${email}. Ask the operator for the code, then run the command in nextStep with it.`,
            nextStep,
          },
          render: () => {
            console.log(`\n• Sent a code to ${email}. Check your inbox.`);
            console.log(`  Re-run with the code to finish: ${nextStep}`);
          },
        });
      }

      if (!json) console.log(`\n• Sent a code to ${email}. Check your inbox.`);

      // 5. Prompt for the code from the email.
      codeToVerify = (
        await inputOrFail(json, { message: "Enter the code:" }, nonInteractive)
      ).trim();
      if (!codeToVerify) {
        return outputErrorAndExit(
          json,
          "No code entered.",
          "Re-run `zora agent connect-email` to request a new code.",
        );
      }
    }

    // 6. Verify the code and link the email to the account.
    let result;
    try {
      result = await linkEmailWithCode({
        accessToken: account.accessToken,
        email,
        code: codeToVerify,
        appId: options.appId,
        origin: options.origin,
        cookie: account.cookie,
      });
    } catch (err) {
      return outputErrorAndExit(
        json,
        `Could not link ${email}: ${formatError(err)}`,
        "The code may be wrong or expired, or the email may belong to another account. Re-run `zora agent connect-email` to try again.",
      );
    }

    track("cli_agent_connect_email", {
      already_linked: false,
      generated_wallet: resolved.generated,
      output_format: json ? "json" : "text",
    });
    setPersonProperties({ email: result.email });

    outputData(json, {
      json: {
        email: result.email,
        did: account.did,
        address: account.address,
        alreadyLinked: false,
        linkedAccounts: result.linkedAccounts,
        walletSource: resolved.source,
      },
      render: () => {
        console.log("\n✓ Email linked");
        console.log(`  Email:        ${result.email}`);
        console.log(`  Wallet (EOA): ${account.address}`);
        console.log(`  Privy DID:    ${account.did}`);
        if (account.isNewUser) {
          console.log(
            "\n  A new Privy account was created for this wallet, with the email linked to it.",
          );
        }
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
  .option(
    "--force",
    "Skip the confirmation when changing an existing agent's username",
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
      force?: boolean;
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

    // Changing an established agent's username rewrites its public handle (and
    // profile URL); the old handle may then be claimed by someone else. Confirm
    // before renaming. Bio/avatar edits are reversible, so they're not gated.
    if (options.username !== undefined) {
      const existingAgent = peekAgentWallet();
      if (existingAgent && existingAgent.username !== options.username) {
        await confirmAgentAction({
          json,
          force: options.force,
          warning:
            `This changes @${existingAgent.username}'s public username to @${options.username}.\n` +
            `The old handle may be claimed by someone else, and links to it can break.`,
          question: `Rename @${existingAgent.username} to @${options.username}?`,
        });
      }
    }

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

    // Keep the `name` person property in sync when the handle is renamed.
    if (options.username !== undefined) {
      setPersonProperties({ name: profile.username });
    }

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

const DEFAULT_BUDGET_PERIOD: BudgetPeriod = "weekly";

/** Parse and validate a `--period` value, exiting with a clear error otherwise. */
function parseBudgetPeriod(json: boolean, raw: string): BudgetPeriod {
  if (raw === "daily" || raw === "weekly" || raw === "lifetime") return raw;
  return outputErrorAndExit(
    json,
    `Invalid --period: ${raw}`,
    "Use one of: daily, weekly, lifetime.",
  );
}

/**
 * Resolve a spend amount to USD from exactly one of `--usd` / `--eth`. An ETH
 * amount is converted at the current price (shared with the trading commands).
 * Exits with an error on a missing/ambiguous/invalid amount.
 */
async function resolveSpendUsd(
  json: boolean,
  options: { usd?: string; eth?: string },
): Promise<number> {
  const hasUsd = options.usd !== undefined;
  const hasEth = options.eth !== undefined;
  if (hasUsd === hasEth) {
    return outputErrorAndExit(
      json,
      "Pass exactly one of --usd or --eth.",
      "e.g. --usd 25 or --eth 0.01",
    );
  }
  const raw = (hasUsd ? options.usd : options.eth) as string;
  const amount = Number(raw);
  if (!Number.isFinite(amount) || amount <= 0) {
    return outputErrorAndExit(
      json,
      `Invalid amount: ${raw}`,
      "Pass a positive number.",
    );
  }
  if (hasUsd) return amount;
  try {
    return await usdFromEth(amount);
  } catch (err) {
    return outputErrorAndExit(json, formatError(err));
  }
}

const budgetCommand = agentCommand
  .command("budget")
  .description(
    "Set and track a global, wallet-level spending budget that applies across all agent skills.\n" +
      "Skills consult `budget check` before a trade and call `budget record` after — a shared ceiling on top of each skill's own caps.",
  )
  .action(function (this: Command) {
    this.outputHelp();
  });

budgetCommand
  .command("set [amount]")
  .description(
    "Set a global spending budget in USD (e.g. `set 250 --period weekly`), or opt out of any cap with --no-limit.",
  )
  .option(
    "--period <period>",
    "Budget window the cap resets over: daily, weekly, or lifetime",
    DEFAULT_BUDGET_PERIOD,
  )
  .option(
    "--no-limit",
    "Explicitly run with no spending cap — acknowledges the full wallet balance can be spent",
  )
  .action(async function (
    this: Command,
    amount: string | undefined,
    options: { period: string; limit: boolean },
  ) {
    const json = getJson(this);
    // Commander maps `--no-limit` to `limit === false`; omitted leaves it true.
    const optedOut = options.limit === false;
    const period = parseBudgetPeriod(json, options.period);

    if (optedOut && amount !== undefined) {
      return outputErrorAndExit(
        json,
        "Pass an amount or --no-limit, not both.",
        "Use `set <amount>` to cap spending, or `set --no-limit` to opt out.",
      );
    }

    let limitUsd: number | null;
    if (optedOut) {
      limitUsd = null;
    } else {
      if (amount === undefined) {
        return outputErrorAndExit(
          json,
          "Set a USD amount, or pass --no-limit to opt out.",
          "e.g. `zora agent budget set 250 --period weekly`",
        );
      }
      limitUsd = Number(amount);
      if (!Number.isFinite(limitUsd) || limitUsd <= 0) {
        return outputErrorAndExit(
          json,
          `Invalid budget amount: ${amount}`,
          "Pass a positive USD amount, e.g. 250.",
        );
      }
    }

    // Preserve any existing ledger and window start so adjusting the cap keeps
    // the spend already recorded — matching the per-skill "edit cap, keep spend"
    // behavior. A brand-new budget starts its window now.
    const existing = getBudget();
    saveBudget({
      limitUsd,
      period,
      optedOut,
      windowStart: existing?.windowStart ?? new Date().toISOString(),
      ledger: existing?.ledger ?? [],
    });

    track("cli_agent_budget", {
      action: "set",
      opted_out: optedOut,
      period,
      output_format: json ? "json" : "text",
    });

    outputData(json, {
      json: { limitUsd, period, optedOut, path: getBudgetPath() },
      render: () => {
        if (optedOut) {
          console.log("\n✓ Global budget: no limit (opted out)");
          console.log(
            "  All skills may spend up to the full wallet balance. Set a cap any time with `zora agent budget set <amount>`.",
          );
        } else {
          console.log(
            `\n✓ Global budget set: ${formatUsd(limitUsd as number)} (${period})`,
          );
          console.log(
            "  All trading skills will check this cap before each trade.",
          );
        }
        console.log(`  Saved to ${getBudgetPath()}`);
      },
    });
  });

budgetCommand
  .command("info")
  .description(
    "Show the global budget: the cap, the period, how much has been spent in the active window, and what's left.",
  )
  .action(async function (this: Command) {
    const json = getJson(this);
    const state = getBudget();

    if (!state) {
      return outputData(json, {
        json: { configured: false, limitUsd: null, optedOut: false },
        render: () => {
          console.log("\n• No global budget configured.");
          console.log(
            "  Set one with `zora agent budget set <amount>`, or opt out with `zora agent budget set --no-limit`.",
          );
        },
      });
    }

    const now = new Date();
    const result = evaluate(state, 0, now);
    const ms = periodMs(state.period);
    const resetsAt =
      ms === null
        ? null
        : new Date(new Date(result.windowStart).getTime() + ms).toISOString();

    track("cli_agent_budget", {
      action: "info",
      opted_out: state.optedOut,
      period: state.period,
      output_format: json ? "json" : "text",
    });

    outputData(json, {
      json: {
        configured: true,
        limitUsd: state.limitUsd,
        period: state.period,
        optedOut: state.optedOut,
        spent: Number(result.spent.toFixed(6)),
        remaining:
          result.remaining === null
            ? null
            : Number(result.remaining.toFixed(6)),
        windowStart: result.windowStart,
        resetsAt,
        entries: state.ledger.length,
        path: getBudgetPath(),
      },
      render: () => {
        console.log("\nGlobal spending budget");
        if (state.optedOut || state.limitUsd === null) {
          console.log("  Limit:     no limit (opted out)");
          console.log(`  Spent:     ${formatUsd(result.spent)} (tracked)`);
        } else {
          console.log(
            `  Limit:     ${formatUsd(state.limitUsd)} per ${state.period}`,
          );
          console.log(`  Spent:     ${formatUsd(result.spent)}`);
          console.log(
            `  Remaining: ${formatUsd(Math.max(0, result.remaining ?? 0))}`,
          );
        }
        if (resetsAt) console.log(`  Window resets: ${resetsAt}`);
        console.log(`  Trades recorded: ${state.ledger.length}`);
      },
    });
  });

budgetCommand
  .command("check")
  .description(
    "Check whether a prospective spend fits the global budget. Skills call this before a trade and read `allowed` in the JSON.",
  )
  .option("--usd <amount>", "Prospective spend in USD")
  .option(
    "--eth <amount>",
    "Prospective spend in ETH (converted to USD at the current price)",
  )
  .action(async function (
    this: Command,
    options: { usd?: string; eth?: string },
  ) {
    const json = getJson(this);

    // No budget configured or opted out → nothing to enforce; every spend is
    // allowed. Check this BEFORE resolving the amount, so an ETH amount never
    // triggers a price fetch here — a price-feed outage must not break the
    // unconditional call.
    const state = getBudget();
    if (!state || state.optedOut) {
      return outputData(json, {
        json: {
          allowed: true,
          configured: !!state,
          optedOut: state?.optedOut ?? false,
          limitUsd: null,
          remaining: null,
        },
        render: () => {
          if (!state) {
            console.log("✓ Allowed — no global budget configured.");
          } else {
            console.log("✓ Allowed — budget opted out (no limit).");
          }
        },
      });
    }

    const usd = await resolveSpendUsd(json, options);
    const result = evaluate(state, usd, new Date());

    outputData(json, {
      json: {
        allowed: result.allowed,
        configured: true,
        usd: Number(usd.toFixed(6)),
        limitUsd: result.limitUsd,
        spent: Number(result.spent.toFixed(6)),
        remaining:
          result.remaining === null
            ? null
            : Number(result.remaining.toFixed(6)),
        reason: result.reason,
      },
      render: () => {
        if (result.allowed) {
          console.log(
            `✓ Allowed — ${formatUsd(usd)} fits${
              result.remaining === null
                ? " (no limit)"
                : ` (${formatUsd(Math.max(0, result.remaining))} remaining)`
            }.`,
          );
        } else {
          console.log(`✗ Blocked — ${result.reason}`);
        }
      },
    });
  });

budgetCommand
  .command("record")
  .description(
    "Record a completed spend in the global budget ledger. Skills call this after a successful trade.",
  )
  .option("--usd <amount>", "USD value of the trade")
  .option(
    "--eth <amount>",
    "ETH value of the trade (converted to USD at the current price)",
  )
  .requiredOption("--skill <name>", "The skill making the spend, e.g. dca")
  .option("--tx <hash>", "Transaction hash of the trade")
  .action(async function (
    this: Command,
    options: { usd?: string; eth?: string; skill: string; tx?: string },
  ) {
    const json = getJson(this);

    // No budget configured or opted out → nothing to record against, but succeed
    // quietly so skills can call `record` unconditionally after a trade (mirrors
    // `check`). Checked BEFORE resolving the amount so an ETH amount never
    // triggers a price fetch here — a price-feed outage must not break the
    // unconditional call.
    const state = getBudget();
    if (!state || state.optedOut) {
      return outputData(json, {
        json: {
          recorded: false,
          configured: !!state,
          optedOut: state?.optedOut ?? false,
          skill: options.skill,
        },
        render: () => {
          if (!state) {
            console.log(
              "• No global budget configured — nothing to record. Set one with `zora agent budget set <amount>`.",
            );
          } else {
            console.log("• Budget opted out (no limit) — nothing to record.");
          }
        },
      });
    }

    const usd = await resolveSpendUsd(json, options);
    const now = new Date();
    const updated = appendSpend(
      state,
      {
        usd,
        skill: options.skill,
        ...(options.tx ? { txHash: options.tx } : {}),
        at: now.toISOString(),
      },
      now,
    );
    saveBudget(updated);

    const result = evaluate(updated, 0, now);

    track("cli_agent_budget", {
      action: "record",
      skill: options.skill,
      period: state.period,
      output_format: json ? "json" : "text",
    });

    outputData(json, {
      json: {
        recorded: {
          usd: Number(usd.toFixed(6)),
          skill: options.skill,
          txHash: options.tx,
        },
        spent: Number(result.spent.toFixed(6)),
        remaining:
          result.remaining === null
            ? null
            : Number(result.remaining.toFixed(6)),
        limitUsd: state.limitUsd,
      },
      render: () => {
        console.log(`\n✓ Recorded ${formatUsd(usd)} (${options.skill})`);
        console.log(`  Spent:     ${formatUsd(result.spent)}`);
        if (result.remaining !== null) {
          console.log(
            `  Remaining: ${formatUsd(Math.max(0, result.remaining))}`,
          );
        }
      },
    });
  });

budgetCommand
  .command("reset")
  .description(
    "Clear the recorded spend and restart the budget window, keeping the cap and period. Use --clear to remove the budget entirely.",
  )
  .option(
    "--clear",
    "Remove the budget entirely (delete the file) instead of just clearing spend",
  )
  .option("--yes", "Skip the confirmation prompt")
  .action(async function (this: Command, options: { clear?: boolean }) {
    const json = getJson(this);
    const state = getBudget();

    if (!state) {
      return outputData(json, {
        json: { reset: false, configured: false },
        render: () =>
          console.log("\n• No global budget configured — nothing to reset."),
      });
    }

    if (!json && !getYes(this)) {
      const ok = await confirm({
        message: options.clear
          ? "Remove the global budget entirely?"
          : "Clear recorded spend and restart the budget window?",
        default: false,
      });
      if (!ok) safeExit(SUCCESS);
    }

    if (options.clear) {
      clearBudget();
    } else {
      saveBudget({
        limitUsd: state.limitUsd,
        period: state.period,
        optedOut: state.optedOut,
        windowStart: new Date().toISOString(),
        ledger: [],
      });
    }

    track("cli_agent_budget", {
      action: "reset",
      cleared: Boolean(options.clear),
      output_format: json ? "json" : "text",
    });

    outputData(json, {
      json: { reset: true, cleared: Boolean(options.clear) },
      render: () => {
        if (options.clear) {
          console.log("\n✓ Global budget removed.");
        } else {
          console.log("\n✓ Spend cleared and budget window restarted.");
          if (state.limitUsd !== null) {
            console.log(
              `  Limit unchanged: ${formatUsd(state.limitUsd)} per ${state.period}`,
            );
          }
        }
      },
    });
  });
