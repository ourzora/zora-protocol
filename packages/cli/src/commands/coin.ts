import { Command } from "commander";
import { coinCreateCommand } from "./create.js";
import { coinHideCommand, coinUnhideCommand } from "./hide.js";

/**
 * `zora coin` — parent command grouping coin operations: `coin create` (the
 * canonical home for what was the top-level `create` command) plus hiding a
 * coin from your holdings and profile (`coin hide` / `unhide`).
 */
export const coinCommand = new Command("coin")
  .description("Create and manage coins")
  .action(function (this: Command) {
    this.outputHelp();
  });

coinCommand.addCommand(coinCreateCommand);
coinCommand.addCommand(coinHideCommand);
coinCommand.addCommand(coinUnhideCommand);
