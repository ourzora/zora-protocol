import { defineConfig } from "tsup";
import pkg from "./package.json";

export default defineConfig({
  entry: ["src/index.tsx"],
  format: ["esm"],
  target: "node20",
  clean: true,
  // Keep both XMTP SDK specifiers external so the per-platform dynamic import in
  // load-xmtp-sdk.ts resolves them at runtime from node_modules. `@xmtp/node-sdk`
  // is auto-externalized as a dependency; the aliased low-glibc package must be
  // listed explicitly.
  external: ["@xmtp/node-sdk", "@xmtp/node-sdk-lowglibc"],
  define: {
    PKG_VERSION: JSON.stringify(pkg.version),
  },
  banner: {
    js: "#!/usr/bin/env node",
  },
});
