import { REQUIRED_GLIBC, detectGlibc } from "./native-binding.js";

/**
 * Per-platform selection of the XMTP SDK, so DMs work on every Linux libc.
 *
 * The native binding is the catch: no single published `@xmtp/node-bindings`
 * build loads on both common-glibc servers and musl.
 *   - The default `@xmtp/node-sdk` (→ node-bindings 1.10.0) ships a linux-gnu
 *     binary that needs glibc 2.38 — too new for Ubuntu 22.04 (2.35), Debian 12
 *     / node:20-24 (2.36), and many GCP/VPS images — but its musl binary works.
 *   - The matched low-glibc build (`@xmtp/node-sdk-lowglibc`, an alias for a
 *     node-sdk whose node-bindings 1.11.0 has a gnu floor of ~2.25/2.34) loads on
 *     those servers, but its musl binary is broken (TLS relocation).
 *
 * So we pick the SDK whose binding can load here:
 *   - musl (glibc undefined), macOS, Windows, or glibc >= 2.38 → default SDK
 *   - glibc Linux below 2.38 → the low-glibc SDK
 * We import the *matched* package (its JS configures its own binding's logging),
 * which keeps stdout clean — mixing one SDK's JS with the other's binary leaks
 * libxmtp logs onto stdout and corrupts `--json`.
 *
 * `@xmtp/node-sdk-lowglibc` is an **optional** dependency. If it isn't installed
 * (e.g. the pinned build was unpublished), we fall back to the default SDK, whose
 * load failure is then turned into the actionable message by `native-binding.ts`.
 *
 * Caveat: the low-glibc build's `engines` require Node 22+, so npm skips this
 * optional dependency on Node 20. Node 20 + old-glibc therefore falls through to
 * the default SDK → the actionable message (use Alpine, Node 22+, or new glibc).
 * The fix is out-of-the-box on Node 22+ (any libc) and on musl / new-glibc at any
 * Node version.
 */

// glibc versions are only ever compared at major.minor (e.g. "2.38"); the patch
// component is never present, so truncating to two numbers is intentional.
const parseVer = (v: string): [number, number] => {
  const [major = 0, minor = 0] = v.split(".").map((n) => parseInt(n, 10) || 0);
  return [major, minor];
};

/** True when glibc version `a` is older than `b` (compares major.minor). Exported for tests. */
export const glibcOlderThan = (a: string, b: string): boolean => {
  const [aMaj, aMin] = parseVer(a);
  const [bMaj, bMin] = parseVer(b);
  return aMaj !== bMaj ? aMaj < bMaj : aMin < bMin;
};

/**
 * True when this host is glibc Linux whose glibc is older than the default
 * binding's floor — i.e. the low-glibc SDK should be used. False on musl (its
 * `glibcVersionRuntime` is undefined and the default SDK's musl binary works),
 * macOS, Windows, and new-enough glibc.
 */
export const shouldUseLowGlibcSdk = (): boolean => {
  if (process.platform !== "linux") return false;
  const glibc = detectGlibc();
  if (!glibc) return false;
  return glibcOlderThan(glibc, REQUIRED_GLIBC);
};

/** The XMTP SDK module shape (both packages share it — the alias is a node-sdk). */
export type XmtpSdk = typeof import("@xmtp/node-sdk");

/**
 * Load the XMTP SDK whose native binding can load on this platform. Prefers the
 * default SDK; only reaches for the low-glibc build on an old-glibc Linux host,
 * and falls back to the default if that optional build isn't installed.
 */
export const loadXmtpSdk = async (): Promise<XmtpSdk> => {
  if (shouldUseLowGlibcSdk()) {
    try {
      return (await import("@xmtp/node-sdk-lowglibc")) as unknown as XmtpSdk;
    } catch {
      // Optional low-glibc build not present — fall through to the default SDK.
      // Its glibc load error becomes the actionable message in native-binding.ts.
    }
  }
  return import("@xmtp/node-sdk");
};
