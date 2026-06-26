import { Command } from "commander";
import { coinCreateCommand } from "./create.js";

/**
 * `zora coin` — parent command grouping coin operations. Today it hosts
 * `coin create` (the canonical home for what was the top-level `create`
 * command); future coin operations can be added as further subcommands.
 */
export const coinCommand = new Command("coin")
  .description("Create and manage coins")
  .action(function (this: Command) {
    this.outputHelp();
  });

coinCommand.addCommand(coinCreateCommand);
