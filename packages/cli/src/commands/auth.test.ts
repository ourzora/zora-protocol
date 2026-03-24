import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { createProgram } from "../test/create-program.js";
import { getApiKey, getEnvApiKey } from "../lib/config.js";
import { authCommand } from "./auth.js";

vi.mock("../lib/config.js", () => ({
  getApiKey: vi.fn(),
  getEnvApiKey: vi.fn(),
  saveApiKey: vi.fn(),
  getConfigPath: vi.fn(() => "/home/user/.config/zora/config.json"),
}));

vi.mock("../lib/mask-key.js", () => ({
  maskKey: vi.fn((k: string) => `***${k.slice(-4)}`),
}));

vi.mock("../lib/prompt.js", () => ({
  passwordOrFail: vi.fn(),
}));

describe("auth status", () => {
  let logSpy: ReturnType<typeof vi.spyOn>;

  beforeEach(() => {
    logSpy = vi.spyOn(console, "log").mockImplementation(() => {});
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  it("shows rate-limit message when no API key is configured", async () => {
    vi.mocked(getApiKey).mockReturnValue(undefined);

    const program = createProgram(authCommand);
    await program.parseAsync(["auth", "status"], { from: "user" });

    const output = logSpy.mock.calls.map((c) => c[0]).join("\n");
    expect(output).toContain("No API key configured");
    expect(output).toContain("rate-limited");
    expect(output).toContain("zora auth configure");
  });

  it("shows masked key and config file source when key is configured", async () => {
    vi.mocked(getApiKey).mockReturnValue("sk-test-abcdef1234");
    vi.mocked(getEnvApiKey).mockReturnValue(undefined);

    const program = createProgram(authCommand);
    await program.parseAsync(["auth", "status"], { from: "user" });

    const output = logSpy.mock.calls.map((c) => c[0]).join("\n");
    expect(output).toContain("Authenticated");
    expect(output).toContain("1234");
    expect(output).toContain("/home/user/.config/zora/config.json");
  });

  it("shows env source when key comes from ZORA_API_KEY", async () => {
    vi.mocked(getApiKey).mockReturnValue("sk-env-key-5678");
    vi.mocked(getEnvApiKey).mockReturnValue("sk-env-key-5678");

    const program = createProgram(authCommand);
    await program.parseAsync(["auth", "status"], { from: "user" });

    const output = logSpy.mock.calls.map((c) => c[0]).join("\n");
    expect(output).toContain("Authenticated");
    expect(output).toContain("env (ZORA_API_KEY)");
  });

  it("outputs JSON for auth status with --json", async () => {
    vi.mocked(getApiKey).mockReturnValue("sk-test-abcdef1234");
    vi.mocked(getEnvApiKey).mockReturnValue(undefined);

    const program = createProgram(authCommand);
    await program.parseAsync(["auth", "status", "--json"], { from: "user" });

    const output = logSpy.mock.calls.map((c) => c[0]).join("\n");
    const parsed = JSON.parse(output);
    expect(parsed.authenticated).toBe(true);
    expect(parsed.source).toContain("config.json");
  });
});
