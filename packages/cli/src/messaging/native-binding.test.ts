import { afterEach, describe, expect, it, vi } from "vitest";
import {
  detectGlibc,
  isNativeBindingError,
  nativeBindingErrorHelp,
} from "./native-binding.js";

/**
 * The error node-bindings actually throws on a too-old-glibc Linux server,
 * reproduced from `zora dm send` on node:20-slim (glibc 2.36). The useful signal
 * is nested two `cause` levels deep; the top-level message is misleading. A naive
 * `err.message` check would miss it — this test guards against that regression.
 */
const realGlibcError = (): Error => {
  const dlopen = new Error(
    "/lib/x86_64-linux-gnu/libc.so.6: version `GLIBC_2.38' not found " +
      "(required by /usr/local/lib/node_modules/@zoralabs/cli/node_modules/" +
      "@xmtp/node-bindings/dist/bindings_node.linux-x64-gnu.node)",
  );
  (dlopen as NodeJS.ErrnoException).code = "ERR_DLOPEN_FAILED";

  const moduleNotFound = new Error(
    "Cannot find module '@xmtp/node-bindings-linux-x64-gnu'",
    { cause: dlopen },
  );
  (moduleNotFound as NodeJS.ErrnoException).code = "MODULE_NOT_FOUND";

  return new Error(
    "Cannot find native binding. npm has a bug related to optional " +
      "dependencies (https://github.com/npm/cli/issues/4828).",
    { cause: moduleNotFound },
  );
};

describe("isNativeBindingError", () => {
  it("detects the real nested glibc-too-old error from a Linux server", () => {
    expect(isNativeBindingError(realGlibcError())).toBe(true);
  });

  it("detects the top-level 'cannot find native binding' rethrow alone", () => {
    expect(isNativeBindingError(new Error("Cannot find native binding."))).toBe(
      true,
    );
  });

  it("detects a bare shared-object load failure", () => {
    expect(
      isNativeBindingError(
        new Error("cannot open shared object file: No such file or directory"),
      ),
    ).toBe(true);
  });

  it("detects a raw ERR_DLOPEN_FAILED code with no telltale message", () => {
    const err = new Error("dlopen failed");
    (err as NodeJS.ErrnoException).code = "ERR_DLOPEN_FAILED";
    expect(isNativeBindingError(err)).toBe(true);
  });

  it("does not flag unrelated runtime errors", () => {
    expect(isNativeBindingError(new Error("fetch failed: ECONNREFUSED"))).toBe(
      false,
    );
    expect(
      isNativeBindingError(new Error("Your Zora smart wallet is not deployed")),
    ).toBe(false);
    expect(isNativeBindingError(undefined)).toBe(false);
  });

  it("terminates on a self-referential cause chain", () => {
    const a = new Error("loop a");
    const b = new Error("loop b", { cause: a });
    (a as { cause?: unknown }).cause = b;
    expect(isNativeBindingError(a)).toBe(false);
  });
});

describe("detectGlibc", () => {
  afterEach(() => vi.restoreAllMocks());

  it("reads glibcVersionRuntime from the object getReport() returns at runtime", () => {
    vi.spyOn(process.report, "getReport").mockReturnValue({
      header: { glibcVersionRuntime: "2.36" },
    });
    expect(detectGlibc()).toBe("2.36");
  });

  it("also handles getReport() returning a JSON string (defensive)", () => {
    vi.spyOn(process.report, "getReport").mockReturnValue(
      JSON.stringify({ header: { glibcVersionRuntime: "2.41" } }) as unknown as object,
    );
    expect(detectGlibc()).toBe("2.41");
  });

  it("returns undefined on musl (no glibcVersionRuntime)", () => {
    vi.spyOn(process.report, "getReport").mockReturnValue({
      header: {},
    });
    expect(detectGlibc()).toBeUndefined();
  });
});

describe("nativeBindingErrorHelp", () => {
  afterEach(() => vi.restoreAllMocks());

  it("suggests Alpine, Node 22+, and a new-glibc image", () => {
    const help = nativeBindingErrorHelp();
    expect(help).toMatch(/alpine/i);
    expect(help).toMatch(/Node 22\+/);
    expect(help).toMatch(/native module/i);
  });

  it("names the detected glibc version when available", () => {
    vi.spyOn(process.report, "getReport").mockReturnValue({
      header: { glibcVersionRuntime: "2.35" },
    });
    expect(nativeBindingErrorHelp()).toContain("(glibc 2.35)");
  });
});
