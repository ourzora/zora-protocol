---
"@zoralabs/cli": patch
---

Fix the XMTP native-binding libiconv patch failing to apply inside Nix shells

The macOS libiconv fix for the XMTP native binding now invokes Apple's `otool`, `install_name_tool`, and `codesign` by absolute path (`/usr/bin/...`) instead of relying on `PATH`. Running `pnpm install` from inside a Nix shell previously shadowed these tools, so the patch silently bailed and `zora dm` failed to load the native binding with a `Library not loaded: /nix/store/.../libiconv.2.dylib` error.
