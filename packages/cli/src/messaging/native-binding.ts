/**
 * Detection and user-facing guidance for failures to load the
 * `@xmtp/node-bindings` native addon that powers DMs.
 *
 * This module deliberately imports **nothing** from `@xmtp/*`, so it is safe to
 * import statically and classify the error thrown by the *dynamic* SDK import in
 * `load-xmtp-sdk.ts` / `client.ts` — importing a classifier that itself pulled in
 * the SDK would re-trigger the very crash we are trying to catch.
 *
 * Background: `@xmtp/node-bindings@1.10.0` (pinned by the default `@xmtp/node-sdk`)
 * ships a `linux-*-gnu` binary built against glibc 2.38 — newer than Ubuntu 22.04
 * (2.35), Debian 12 / node:20-24 (2.36), and many GCP/VPS images. `load-xmtp-sdk.ts`
 * works around this by selecting a matched low-glibc SDK build on those hosts, so
 * DMs work out of the box. This module is the **last resort** for when even that
 * can't load: the optional low-glibc build wasn't installed, the host glibc is
 * older than the low-glibc binary's floor (~2.25), or some other binding failure.
 *
 * The failure surfaces as a misleading top-level Error ("Cannot find native
 * binding. npm has a bug related to optional dependencies…") whose useful cause
 * (`GLIBC_… not found`, `ERR_DLOPEN_FAILED`) is nested two `cause` levels deep, so
 * we walk the entire `cause` chain rather than inspecting only `err.message`.
 */

/**
 * Glibc floor of the default (`@xmtp/node-sdk` → node-bindings 1.10.0) `linux-*-gnu`
 * binary. Used by `load-xmtp-sdk.ts` as the threshold below which it switches to
 * the low-glibc SDK build.
 */
export const REQUIRED_GLIBC = "2.38";

/** Flatten an error and its nested `cause` chain into one searchable string. */
const errorChainText = (err: unknown): string => {
  const parts: string[] = [];
  const seen = new Set<unknown>();
  let cur: unknown = err;
  while (cur && !seen.has(cur)) {
    seen.add(cur);
    if (cur instanceof Error) {
      parts.push(cur.message);
      const code = (cur as NodeJS.ErrnoException).code;
      if (code) parts.push(code);
      cur = (cur as { cause?: unknown }).cause;
    } else {
      parts.push(String(cur));
      break;
    }
  }
  return parts.join("\n");
};

/**
 * True when `err` (or anything in its `cause` chain) is a failure to load the
 * XMTP native binding. Covers the glibc-version mismatch, a raw dlopen failure,
 * a missing shared object, the node-bindings "cannot find native binding"
 * rethrow, and the `MODULE_NOT_FOUND` for its per-platform package.
 *
 * Patterns are intentionally specific: a substring match on `node-bindings` would
 * also swallow a *runtime* error from a successfully loaded binding that embeds
 * its own filename in the message (common for Rust/NAPI panics), so the package
 * specifier is matched path-qualified (`@xmtp/node-bindings`) rather than loosely.
 */
export const isNativeBindingError = (err: unknown): boolean => {
  const text = errorChainText(err);
  return (
    /ERR_DLOPEN_FAILED/.test(text) ||
    /\bdlopen\b/i.test(text) ||
    /GLIBC_[\d.]+'? not found/i.test(text) ||
    /cannot open shared object/i.test(text) ||
    /cannot find native binding/i.test(text) ||
    /@xmtp\/node-bindings/i.test(text)
  );
};

/**
 * Runtime glibc version (e.g. "2.36"), or undefined on musl / when unknown.
 * Exported so the SDK selector (load-xmtp-sdk.ts) shares one implementation.
 * `process.report.getReport()` returns a JS object; we also accept a JSON string
 * defensively, since its return shape has varied across Node / `@types/node`
 * versions, and `JSON.parse` handles either without a fragile cast.
 */
export const detectGlibc = (): string | undefined => {
  try {
    const raw = process.report?.getReport?.() as unknown;
    const report = (typeof raw === "string" ? JSON.parse(raw) : raw) as
      | { header?: { glibcVersionRuntime?: string } }
      | undefined;
    return report?.header?.glibcVersionRuntime || undefined;
  } catch {
    return undefined;
  }
};

/**
 * The remediation text shown when the native binding can't load. Names the
 * detected glibc when available, then lists the known-good environments. These
 * are the cases the runtime SDK selector can't cover: notably Node 20 on old
 * glibc, where npm skips the low-glibc build (its `engines` require Node 22+).
 */
export const nativeBindingErrorHelp = (): string => {
  const glibc = detectGlibc();
  const where = glibc ? ` (glibc ${glibc})` : "";
  return [
    `The XMTP messaging library's native module couldn't load on this system${where}.`,
    "",
    "DMs need a platform-native binary. Any of these fixes it:",
    "  • run on an Alpine / musl image — e.g. node:20-alpine (works on any Node version)",
    "  • use Node 22+ and reinstall the CLI — `npm install -g @zoralabs/cli`",
    `  • or use a glibc >= ${REQUIRED_GLIBC} image — Ubuntu 24.04+ or Debian 13`,
  ].join("\n");
};
