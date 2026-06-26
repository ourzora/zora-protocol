import { describe, it, expect, vi } from "vitest";

vi.mock("../lib/analytics.js", () => ({
  track: vi.fn(),
  identify: vi.fn(),
  shutdownAnalytics: vi.fn(),
}));

// Importing the full `buildProgram` pulls in every command module. `../lib/config.js`
// resolves the config directory at module load (via os.homedir()), which is unsafe
// under vitest, so mock it out — these tests never touch config.
vi.mock("../lib/config.js", () => ({
  getApiKey: vi.fn(),
  getPrivateKey: vi.fn(),
  getSmartWalletAddress: vi.fn(),
  getAgentWallet: vi.fn(),
  isAgentWallet: vi.fn(),
  peekAgentWallet: vi.fn(),
  getEnvApiKey: vi.fn(),
  getAnalyticsId: vi.fn(),
  getDmCheckAt: vi.fn(),
  saveDmCheckAt: vi.fn(),
  getPrivySession: vi.fn(),
  getBudget: vi.fn(),
}));

// buildProgram's postAction hook surfaces new DMs; stub it so these tests don't
// hit the network or filesystem for messaging.
vi.mock("../messaging/notify.js", () => ({
  maybeNotifyNewDms: vi.fn().mockResolvedValue(undefined),
}));

import { createProgram } from "../test/create-program.js";
import { buildProgram } from "../index.js";
import { coinCommand } from "./coin.js";

// These drive the real `buildProgram()` (not the lightweight `createProgram`
// harness) so they prove the commands are actually wired into the CLI.
describe("coin command registration", () => {
  it("registers a top-level `coin` command with its subcommands", () => {
    const program = buildProgram();
    const coin = program.commands.find((c) => c.name() === "coin");
    expect(coin).toBeDefined();
    const subcommands = coin!.commands.map((c) => c.name());
    expect(subcommands).toEqual(
      expect.arrayContaining(["create", "hide", "unhide"]),
    );
  });

  it("keeps the deprecated top-level `create` command registered", () => {
    const program = buildProgram();
    expect(program.commands.map((c) => c.name())).toContain("create");
  });
});

describe("bare `zora coin`", () => {
  it("shows help when invoked with no subcommand", async () => {
    const helpSpy = vi
      .spyOn(coinCommand, "outputHelp")
      .mockImplementation(() => {});
    const program = createProgram(coinCommand);
    await program.parseAsync(["coin"], { from: "user" });
    expect(helpSpy).toHaveBeenCalled();
    helpSpy.mockRestore();
  });
});
