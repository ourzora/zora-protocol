import { Command } from "commander";
import { ExitPromptError } from "@inquirer/core";
import { readFileSync } from "node:fs";
import { setApiBaseUrl } from "@zoralabs/coins-sdk";
import { authCommand } from "./commands/auth.js";
import { balanceCommand } from "./commands/balance.js";
import { buyCommand } from "./commands/buy.js";
import { exploreCommand } from "./commands/explore.jsx";
import { getCommand } from "./commands/get.jsx";
import { priceHistoryCommand } from "./commands/price-history.jsx";
import { sellCommand } from "./commands/sell.js";
import { setupCommand } from "./commands/setup.js";
import { walletCommand } from "./commands/wallet.js";
import { renderOnce } from "./lib/render.js";
import { Zorb } from "./components/Zorb.js";
import { supportsTruecolor } from "./lib/zorb-pixels.js";
import { identify, shutdownAnalytics } from "./lib/analytics.js";

declare const PKG_VERSION: string | undefined;

// Override SDK base URL via ZORA_API_TARGET (e.g. http://localhost:3000, staging URL)
if (process.env.ZORA_API_TARGET) {
  setApiBaseUrl(process.env.ZORA_API_TARGET);
}

const version =
  typeof PKG_VERSION !== "undefined"
    ? PKG_VERSION
    : JSON.parse(
        readFileSync(new URL("../package.json", import.meta.url), "utf-8"),
      ).version;

const buildProgram = (): Command => {
  const program = new Command()
    .name("zora")
    .description("Zora CLI")
    .version(version)
    .option("--json", "Output as JSON (for scripts and automation)", false);

  program.addCommand(authCommand);
  program.addCommand(balanceCommand);
  program.addCommand(buyCommand);
  program.addCommand(exploreCommand);
  program.addCommand(getCommand);
  program.addCommand(priceHistoryCommand);
  program.addCommand(setupCommand);
  program.addCommand(walletCommand);
  program.addCommand(sellCommand);

  return program;
};

const program = buildProgram();

if (!process.env.VITEST) {
  const showingHelp =
    process.argv.length <= 2 ||
    process.argv.includes("--help") ||
    process.argv.includes("-h");
  if (showingHelp && !process.argv.includes("--json") && supportsTruecolor()) {
    renderOnce(<Zorb size={20} />);
  }

  identify();

  try {
    await program.parseAsync();
  } catch (err) {
    if (err instanceof ExitPromptError) {
      console.log("\nAborted.");
      process.exit(0);
    }
    throw err;
  } finally {
    await shutdownAnalytics();
  }
}

export { buildProgram };
