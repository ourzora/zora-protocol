import { Command } from "commander";

/**
 * Creates a root program with global options and attaches the given command.
 * Needed because optsWithGlobals() requires the command to have a parent
 * with the global options defined.
 */
const createProgram = (subcommand: Command): Command => {
  const program = new Command()
    .name("zora")
    .option("--json", "Output as JSON (for scripts and automation)", false)
    .option("--yes", "Skip interactive prompts", false);

  program.addCommand(subcommand);
  return program;
};

export { createProgram };
