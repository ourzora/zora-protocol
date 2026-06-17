import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { homedir, platform } from "node:os";
import { dirname, join } from "node:path";

/** A cached Zora profile keyed by lowercased address (handles change rarely). */
export interface CachedProfile {
  handle: string | null;
  displayName: string | null;
  avatarUrl: string | null;
  /** True if this profile has been blocked by the platform. */
  platformBlocked?: boolean;
  /** Epoch ms the entry was fetched, for TTL-based refresh. */
  fetchedAt: number;
}

/** Max cached profiles kept on disk; oldest are evicted past this. */
const MAX_ENTRIES = 5000;

// Resolved lazily (not at module load) so importing this module never calls
// homedir() — keeps it safe to import at the top of files/tests before the home
// directory is established.
function cacheFile(): string {
  const dir =
    platform() === "win32"
      ? join(
          process.env.APPDATA ?? join(homedir(), "AppData", "Roaming"),
          "zora",
        )
      : join(homedir(), ".config", "zora");
  return join(dir, "profiles.json");
}

/** Reads the address→profile cache. Best-effort: returns {} on any problem. */
export function readProfileCache(): Record<string, CachedProfile> {
  try {
    const file = cacheFile();
    if (!existsSync(file)) return {};
    const parsed = JSON.parse(readFileSync(file, "utf-8"));
    return parsed?.profiles ?? {};
  } catch {
    return {};
  }
}

/**
 * Persists the address→profile cache, evicting the oldest entries past
 * {@link MAX_ENTRIES}. Best-effort: write failures are swallowed (the cache is a
 * convenience; resolution still works without it).
 */
export function writeProfileCache(cache: Record<string, CachedProfile>): void {
  try {
    let entries = Object.entries(cache);
    if (entries.length > MAX_ENTRIES) {
      entries = entries
        .sort((a, b) => b[1].fetchedAt - a[1].fetchedAt)
        .slice(0, MAX_ENTRIES);
    }
    const file = cacheFile();
    mkdirSync(dirname(file), { recursive: true });
    writeFileSync(
      file,
      JSON.stringify({ version: 1, profiles: Object.fromEntries(entries) }) +
        "\n",
    );
  } catch {
    // ignore — the cache is best-effort
  }
}
