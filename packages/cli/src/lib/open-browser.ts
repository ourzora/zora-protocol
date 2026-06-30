import { spawn } from "node:child_process";

/**
 * Open `url` in the user's default browser, returning whether the launcher was
 * spawned successfully. Best-effort and non-throwing: callers should print the
 * URL as a fallback so the flow still works on headless or locked-down hosts.
 *
 * Uses the platform's native opener (`open` on macOS, `start` on Windows,
 * `xdg-open` elsewhere) rather than adding a dependency.
 */
export function openBrowser(url: string): boolean {
  const { command, args } = launcherFor(url);
  try {
    const child = spawn(command, args, {
      stdio: "ignore",
      // `start` is a cmd.exe builtin, so it needs a shell on Windows.
      shell: process.platform === "win32",
      detached: true,
    });
    child.on("error", () => {});
    child.unref();
    return true;
  } catch {
    return false;
  }
}

function launcherFor(url: string): { command: string; args: string[] } {
  switch (process.platform) {
    case "darwin":
      return { command: "open", args: [url] };
    case "win32":
      // Under cmd.exe (shell: true), `&` is a command separator, so an unquoted
      // OAuth URL would be truncated at its first query param. Quote the URL to
      // keep it intact. The leading "" is `start`'s window-title argument —
      // required because a quoted first arg would otherwise be taken as the title.
      return { command: "start", args: ['""', `"${url}"`] };
    default:
      return { command: "xdg-open", args: [url] };
  }
}
