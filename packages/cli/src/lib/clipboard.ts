import { execFileSync } from "node:child_process";
import { platform } from "node:os";

export const copyToClipboard = (text: string): boolean => {
  const os = platform();
  try {
    if (os === "darwin") {
      execFileSync("pbcopy", {
        input: text,
        stdio: ["pipe", "ignore", "ignore"],
      });
    } else if (os === "linux") {
      execFileSync("xclip", ["-selection", "clipboard"], {
        input: text,
        stdio: ["pipe", "ignore", "ignore"],
      });
    } else if (os === "win32") {
      execFileSync("clip", {
        input: text,
        stdio: ["pipe", "ignore", "ignore"],
      });
    } else {
      return false;
    }
    return true;
  } catch {
    return false;
  }
};
