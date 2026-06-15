// Work around an upstream packaging bug in @xmtp/node-bindings (present in 1.10.0,
// the version pulled in by @xmtp/node-sdk@6): the prebuilt macOS .node files link
// libiconv from a Nix store path (e.g. /nix/store/<hash>-libiconv-*/lib/libiconv.2.dylib)
// instead of the system one. On a stock Mac dyld falls back to /usr/lib and it
// loads, but environments that override DYLD_FALLBACK_LIBRARY_PATH (Nix shells,
// some sandboxes) can't fall back, so `Client.create` fails with a dlopen error.
//
// This repoints that load command to /usr/lib/libiconv.2.dylib in the installed
// .node so the binding loads on any Mac. It runs from `build`/`build:js` (fixes
// the node_modules install for source/dev runs), `postinstall` (npm i -g), and
// before `bun build --compile` for the `build:binary:mac-*` targets.
//
// Safe by design — exits 0 (no-op) when:
//   • not running on macOS (the only place install_name_tool/codesign exist),
//   • @xmtp/node-bindings isn't installed,
//   • no macOS .node files are present,
//   • the binding is already correctly linked (e.g. after XMTP ships a fix).
// Because it keys off the build *host* (process.platform), the macOS targets must
// be built on a macOS runner for the fix to apply (which signed releases need anyway).

import { execFileSync } from "node:child_process";
import { createRequire } from "node:module";
import { dirname, join } from "node:path";
import { existsSync, copyFileSync, renameSync } from "node:fs";

const SYSTEM_LIBICONV = "/usr/lib/libiconv.2.dylib";
const log = (msg) => console.log(`[patch-xmtp-binding] ${msg}`);

if (process.platform !== "darwin") {
  log(`skipping on ${process.platform} — macOS-only fix`);
  process.exit(0);
}

let distDir;
try {
  // @xmtp/node-bindings is a transitive dep (via @xmtp/node-sdk), so under pnpm's
  // strict node_modules it can't be resolved directly from here. Resolve node-sdk
  // (a direct dep) first, then node-bindings from there. Its `exports` only expose
  // ".", so resolve the entry (./dist/index.js) and take its directory — that's
  // where the platform .node files live.
  const require = createRequire(import.meta.url);
  const sdkRequire = createRequire(require.resolve("@xmtp/node-sdk"));
  distDir = dirname(sdkRequire.resolve("@xmtp/node-bindings"));
} catch (err) {
  log(`@xmtp/node-bindings not found (${err.message}) — nothing to patch`);
  process.exit(0);
}

const targets = [
  "bindings_node.darwin-arm64.node",
  "bindings_node.darwin-x64.node",
]
  .map((f) => join(distDir, f))
  .filter(existsSync);

if (targets.length === 0) {
  log("no macOS .node files present — nothing to patch");
  process.exit(0);
}

// Resolve Apple's toolchain by absolute path so the patch still applies when run
// inside a Nix shell (or anything else that shadows these tools on PATH) — the
// case that left the binding broken for some contributors. `/usr/bin/{otool,
// install_name_tool,codesign}` are Apple stubs that dispatch through the active
// Xcode toolchain regardless of PATH. Falls back to a bare PATH lookup if the
// system copy isn't where we expect.
const systemTool = (name) =>
  existsSync(`/usr/bin/${name}`) ? `/usr/bin/${name}` : name;
const OTOOL = systemTool("otool");
const INSTALL_NAME_TOOL = systemTool("install_name_tool");
const CODESIGN = systemTool("codesign");

const run = (cmd, args) => execFileSync(cmd, args, { encoding: "utf8" });

let patched = 0;
for (const file of targets) {
  let deps;
  try {
    deps = run(OTOOL, ["-L", file]);
  } catch (err) {
    // Xcode command line tools unavailable — warn but don't fail the build.
    log(
      `otool unavailable (${err.message}); skipping — install Xcode CLT to apply the fix`,
    );
    process.exit(0);
  }

  // The load command for libiconv that isn't already the system path.
  const bad = deps
    .split("\n")
    .map((line) => line.trim().split(/\s+/)[0])
    .find((p) => /\/libiconv\.2\.dylib$/.test(p) && p !== SYSTEM_LIBICONV);

  if (!bad) {
    log(`already OK: ${file}`);
    continue;
  }

  try {
    log(`repointing libiconv: ${bad} -> ${SYSTEM_LIBICONV}`);
    // Break the hard link into the pnpm store so we edit a private copy in
    // node_modules, never the shared store object other projects link to.
    const tmp = `${file}.patching`;
    copyFileSync(file, tmp);
    renameSync(tmp, file);
    run(INSTALL_NAME_TOOL, ["-change", bad, SYSTEM_LIBICONV, file]);
    // Editing load commands invalidates the signature; re-sign ad-hoc so the
    // embedded binary still loads under macOS code-signing checks.
    run(CODESIGN, ["-f", "-s", "-", file]);
    patched += 1;
  } catch (err) {
    // Best-effort: never fail the caller (build / postinstall). On a stock Mac
    // the dyld /usr/lib fallback still loads the binding without this patch.
    log(`could not patch ${file} (${err.message}); leaving as-is`);
  }
}

log(`done — ${patched} file(s) patched`);
