import { mkdtempSync, rmSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { vi, beforeEach, afterEach } from "vitest";

let tmpDir: string;

vi.mock("node:os", async (importOriginal) => {
  const actual = await importOriginal<typeof import("node:os")>();
  return {
    ...actual,
    homedir: () => tmpDir,
  };
});

beforeEach(() => {
  tmpDir = mkdtempSync(join(tmpdir(), "zora-cli-test-"));
  vi.resetModules();
});

afterEach(() => {
  rmSync(tmpDir, { recursive: true, force: true });
});

export function getTestHomeDir(): string {
  return tmpDir;
}
