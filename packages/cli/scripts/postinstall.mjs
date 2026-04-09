#!/usr/bin/env node

import path from "node:path";
import os from "node:os";

try {
  if (process.env.npm_config_global !== "true") {
    process.exit(0);
  }

  const prefix = process.env.npm_config_prefix;
  if (!prefix) {
    process.exit(0);
  }

  const npmBin =
    process.platform === "win32" ? prefix : path.join(prefix, "bin");

  const pathDirs = (process.env.PATH || "").split(path.delimiter);
  const resolved = path.resolve(npmBin);
  const inPath = pathDirs.some((dir) => path.resolve(dir) === resolved);

  if (inPath) {
    process.exit(0);
  }

  const tty = process.stdout.isTTY && !process.env.NO_COLOR;
  const YELLOW = tty ? "\x1b[33m" : "";
  const BOLD = tty ? "\x1b[1m" : "";
  const DIM = tty ? "\x1b[2m" : "";
  const RESET = tty ? "\x1b[0m" : "";

  const shell = (process.env.SHELL || "").split("/").pop();
  const isFish = shell === "fish";

  let lines = [];
  lines.push("");
  lines.push(
    `${YELLOW}\u26a0${RESET}  ${BOLD}zora${RESET} is not in your PATH.`,
  );
  lines.push("");
  lines.push(`${DIM}   To fix, run:${RESET}`);
  lines.push("");

  if (process.platform === "win32") {
    lines.push(
      `     powershell -c "[Environment]::SetEnvironmentVariable('Path',[Environment]::GetEnvironmentVariable('Path','User')+';${npmBin}','User')"`,
    );
  } else if (isFish) {
    lines.push(`     fish_add_path ${npmBin}`);
  } else {
    const exportCmd = `export PATH="${npmBin}:$PATH"`;

    let rcFile;
    if (shell === "zsh") {
      rcFile = "~/.zshrc";
    } else if (shell === "bash") {
      rcFile = os.platform() === "darwin" ? "~/.bash_profile" : "~/.bashrc";
    }

    lines.push(`     ${exportCmd}`);

    if (rcFile) {
      lines.push(`     echo '${exportCmd}' >> ${rcFile}`);
    }
  }

  lines.push("");
  console.log(lines.join("\n"));
} catch {
  // Never fail the install
}
