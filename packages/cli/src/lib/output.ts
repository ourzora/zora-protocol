import type { Command } from "commander";

type OutputMode = "static" | "json" | "live";

const getOutputMode = (cmd: Command, defaultMode: OutputMode): OutputMode => {
  const globals = cmd.optsWithGlobals();
  const json = (globals.json ?? false) as boolean;
  const live = (globals.live ?? false) as boolean;
  const static_ = (globals.static ?? false) as boolean;

  const set = [
    json && "--json",
    live && "--live",
    static_ && "--static",
  ].filter(Boolean) as string[];

  if (set.length > 1) {
    return outputErrorAndExit(
      false,
      `${set.join(", ")} cannot be used together.`,
      "Choose one: --json, --live, or --static",
    );
  }

  if (json) return "json";
  if (live) return "live";
  if (static_) return "static";
  return defaultMode;
};

const getJson = (cmd: Command): boolean =>
  (cmd.optsWithGlobals().json ?? false) as boolean;

const getYes = (cmd: Command): boolean =>
  (cmd.optsWithGlobals().yes ?? false) as boolean;

const outputJson = (data: unknown): void => {
  console.log(JSON.stringify(data, null, 2));
};

const outputErrorAndExit = (
  json: boolean,
  message: string,
  suggestion?: string,
): never => {
  if (json) {
    const payload: { error: string; suggestion?: string } = { error: message };
    if (suggestion) payload.suggestion = suggestion;
    console.log(JSON.stringify(payload, null, 2));
  } else {
    console.error(`\x1b[31mError:\x1b[0m ${message}`);
    if (suggestion) {
      console.error(`\x1b[2m${suggestion}\x1b[0m`);
    }
  }
  process.exit(1);
};

const outputData = (
  json: boolean,
  opts: { json: unknown; render: () => void },
): void => {
  if (json) {
    outputJson(opts.json);
  } else {
    opts.render();
  }
};

type LiveConfig = { live: boolean; intervalSeconds: number };

const getLiveConfig = (cmd: Command, mode: OutputMode): LiveConfig => {
  const live = mode === "live";
  const intervalRaw = parseInt(cmd.opts().refresh as string, 10);
  const intervalSeconds =
    isNaN(intervalRaw) || intervalRaw < 5 ? 30 : intervalRaw;

  if (!live && cmd.getOptionValueSource("refresh") === "cli") {
    console.warn(
      "\x1b[33mWarning:\x1b[0m --refresh has no effect without --live",
    );
  }

  return { live, intervalSeconds };
};

export {
  getJson,
  getYes,
  getOutputMode,
  getLiveConfig,
  outputJson,
  outputErrorAndExit,
  outputData,
  type OutputMode,
  type LiveConfig,
};
