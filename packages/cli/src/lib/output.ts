import type { Command } from "commander";

type OutputMode = "table" | "json" | "live";

const VALID_OUTPUT_MODES: OutputMode[] = ["table", "json", "live"];

const getOutputMode = (cmd: Command, defaultMode: OutputMode): OutputMode => {
  const raw = cmd.optsWithGlobals().output as string | undefined;
  if (!raw) return defaultMode;
  if (VALID_OUTPUT_MODES.includes(raw as OutputMode)) return raw as OutputMode;
  return outputErrorAndExit(
    false,
    `Invalid --output value: ${raw}.`,
    `Supported: ${VALID_OUTPUT_MODES.join(", ")}`,
  );
};

const getJson = (cmd: Command): boolean =>
  getOutputMode(cmd, "table") === "json";

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
  opts: { json: unknown; table: () => void },
): void => {
  if (json) {
    outputJson(opts.json);
  } else {
    opts.table();
  }
};

type LiveConfig = { live: boolean; intervalSeconds: number };

const getLiveConfig = (cmd: Command, defaultMode: OutputMode): LiveConfig => {
  const mode = getOutputMode(cmd, defaultMode);
  const live = mode === "live";
  const intervalRaw = parseInt(cmd.optsWithGlobals().interval as string, 10);
  const intervalSeconds =
    isNaN(intervalRaw) || intervalRaw < 5 ? 30 : intervalRaw;

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
