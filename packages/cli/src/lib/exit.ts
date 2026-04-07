export const SUCCESS = 0;
export const ERROR = 1;

export class CliExitError extends Error {
  readonly exitCode: number;
  constructor(code: number) {
    super(`process.exit(${code})`);
    this.name = "CliExitError";
    this.exitCode = code;
  }
}

/**
 * Triggers a clean CLI exit. Throws a CliExitError that is caught at the
 * top level where analytics are flushed before the process terminates.
 */
export const safeExit = (code: number): never => {
  throw new CliExitError(code);
};
