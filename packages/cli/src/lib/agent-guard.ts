import { confirmOrDefault } from "./prompt.js";
import { outputErrorAndExit } from "./output.js";
import { warningBox } from "./warning-box.js";
import { safeExit, SUCCESS } from "./exit.js";
import { getWalletPath, type AgentWalletInfo } from "./config.js";

const shortAddr = (addr: string): string =>
  `${addr.slice(0, 6)}…${addr.slice(-4)}`;

/**
 * Guards the IRREVERSIBLE overwrite of a wallet that owns a Zora agent.
 *
 * The agent's EOA is an owner of its smart wallet (baked in at genesis), so
 * replacing the key in `wallet.json` orphans the on-chain account — its coins,
 * posts, and profile become unrecoverable. A plain `--force` (the human path's
 * "yes, overwrite") must NOT be enough to trigger this silently, so this guard
 * is independent of that flag:
 *
 *  - non-interactive (`--yes` / `--json` / no TTY): refuse, since there's no way
 *    to take real consent;
 *  - interactive: explain exactly what will be destroyed and require an explicit
 *    confirmation that defaults to "no".
 *
 * Returns only when the caller may proceed; otherwise it exits the process.
 */
export async function confirmAgentWalletOverwrite(opts: {
  json: boolean;
  nonInteractive: boolean;
  agent: AgentWalletInfo;
}): Promise<void> {
  const { json, nonInteractive, agent } = opts;
  const handle = `@${agent.username}`;

  if (nonInteractive) {
    return outputErrorAndExit(
      json,
      `This wallet controls the Zora agent ${handle} (smart wallet ${agent.smartWalletAddress}). ` +
        `Overwriting it would permanently orphan that account — the new key isn't an owner of the ` +
        `smart wallet, so its coins, posts, and profile become unrecoverable.`,
      `Refusing to do this non-interactively. Re-run without --yes/--json to confirm, or delete ` +
        `${getWalletPath()} yourself if you really intend to.`,
    );
  }

  warningBox(`This wallet controls the Zora agent ${handle}.`);
  console.error(`  Agent:        ${handle}`);
  console.error(`  Smart wallet: ${agent.smartWalletAddress}`);
  console.error(`  Owner (EOA):  ${shortAddr(agent.address)}`);
  console.error(`  Profile:      ${agent.profileUrl}`);
  console.error(
    "\n  Replacing this wallet's key permanently orphans that account: the new key",
  );
  console.error(
    "  is NOT an owner of the smart wallet, so its coins, posts, and profile",
  );
  console.error("  become unrecoverable. This cannot be undone.\n");

  const ok = await confirmOrDefault(
    {
      message: `Overwrite the wallet for agent ${handle}? This is irreversible.`,
      default: false,
    },
    false,
  );
  if (!ok) {
    console.error("Aborted.");
    return safeExit(SUCCESS);
  }
}

/**
 * Confirms a destructive-but-RECOVERABLE action on an existing agent (e.g.
 * re-minting on `agent create`, or renaming on `agent update`). Unlike a key
 * overwrite these can be lived with or redone, so a scripted/headless caller
 * (`--json`, i.e. the agent itself in CI) is allowed to proceed, and an explicit
 * `--force` skips the prompt. Interactive callers get an explanation and a
 * default-"no" confirmation.
 *
 * Callers should only invoke this once they've established the action targets an
 * existing agent (see {@link peekAgentWallet}). Returns when the caller may
 * proceed; otherwise it exits the process.
 */
export async function confirmAgentAction(opts: {
  json: boolean;
  force?: boolean;
  warning: string;
  question: string;
}): Promise<void> {
  if (opts.force) return;
  if (opts.json) return;

  warningBox(opts.warning);
  const ok = await confirmOrDefault(
    { message: opts.question, default: false },
    false,
  );
  if (!ok) {
    console.error("Aborted.");
    return safeExit(SUCCESS);
  }
}
