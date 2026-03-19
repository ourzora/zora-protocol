import type { Command } from "commander";

const getJson = (cmd: Command): boolean =>
  cmd.optsWithGlobals().json as boolean;

const getYes = (cmd: Command): boolean => cmd.optsWithGlobals().yes as boolean;

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

export { getJson, getYes, outputJson, outputErrorAndExit, outputData };
