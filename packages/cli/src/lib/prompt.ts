import confirm from "@inquirer/confirm";
import select from "@inquirer/select";
import password from "@inquirer/password";
import { outputErrorAndExit } from "./output.js";

type ConfirmOpts = {
  message: string;
  default: boolean;
};

const confirmOrDefault = async (
  opts: ConfirmOpts,
  nonInteractive: boolean,
): Promise<boolean> => {
  if (nonInteractive) return true;
  return confirm(opts);
};

type SelectChoice<T> = { name: string; value: T };

type SelectOpts<T> = {
  message: string;
  choices: SelectChoice<T>[];
  default: T;
};

const selectOrDefault = async <T>(
  opts: SelectOpts<T>,
  nonInteractive: boolean,
): Promise<T> => {
  if (nonInteractive) return opts.default;
  return select(opts);
};

type PasswordOpts = {
  message: string;
};

const passwordOrFail = async (
  json: boolean,
  opts: PasswordOpts,
  nonInteractive: boolean,
): Promise<string> => {
  if (nonInteractive) {
    outputErrorAndExit(
      json,
      "This command requires interactive input. Remove --yes to proceed.",
    );
  }
  return password(opts);
};

export { confirmOrDefault, selectOrDefault, passwordOrFail };
