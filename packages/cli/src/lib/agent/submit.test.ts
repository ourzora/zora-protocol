import { describe, it, expect, vi, beforeEach } from "vitest";

vi.mock("./zora-client.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("./zora-client.js")>();
  return { ...actual, trpcRequest: vi.fn() };
});
vi.mock("./user-op.js", () => ({
  parseUserOperation: vi.fn(),
  signUserOp: vi.fn(),
  simulateUserOp: vi.fn(),
  isSponsored: vi.fn(),
}));

import { signSimulateSubmit } from "./submit.js";
import { trpcRequest } from "./zora-client.js";
import {
  parseUserOperation,
  signUserOp,
  simulateUserOp,
  isSponsored,
} from "./user-op.js";

// account/client/raw are only forwarded to the mocked user-op helpers, so the
// concrete values don't matter here.
const params = (over = {}) =>
  ({
    token: "tok",
    account: {},
    client: {},
    raw: { sender: "0xsmart" },
    dryRun: false,
    ...over,
  }) as Parameters<typeof signSimulateSubmit>[0];

beforeEach(() => {
  vi.clearAllMocks();
  vi.mocked(parseUserOperation).mockImplementation((raw) => raw as never);
  vi.mocked(signUserOp).mockResolvedValue({ signature: "0xsig" } as never);
  vi.mocked(simulateUserOp).mockResolvedValue({
    valid: true,
    detail: "ExecutionResult",
  });
  vi.mocked(isSponsored).mockReturnValue(true);
});

describe("signSimulateSubmit", () => {
  it("signs, simulates, and submits — returning the tx hash", async () => {
    vi.mocked(trpcRequest).mockResolvedValue({
      status: 200,
      data: { hash: "0xtx", success: true },
      text: "",
    });
    const result = await signSimulateSubmit(params());
    expect(result.submitted).toEqual({
      hash: "0xtx",
      success: true,
      reason: undefined,
      logs: [],
    });
    expect(result.sponsored).toBe(true);
    expect(result.simulation).toBe("ExecutionResult");
  });

  it("stops after a successful simulation on a dry run", async () => {
    const result = await signSimulateSubmit(params({ dryRun: true }));
    expect(result.submitted).toBeUndefined();
    expect(result.simulation).toBe("ExecutionResult");
    expect(trpcRequest).not.toHaveBeenCalled();
  });

  it("throws when the simulation rejects the op", async () => {
    vi.mocked(simulateUserOp).mockResolvedValue({
      valid: false,
      detail: "AA24 signature error",
    });
    await expect(signSimulateSubmit(params())).rejects.toThrow(
      /would be rejected on-chain.*AA24/s,
    );
    expect(trpcRequest).not.toHaveBeenCalled();
  });

  it("throws when submit returns no hash", async () => {
    vi.mocked(trpcRequest).mockResolvedValue({
      status: 500,
      data: undefined,
      error: "backend boom",
      text: "",
    });
    await expect(signSimulateSubmit(params())).rejects.toThrow(
      /submitUserOperation failed: backend boom/,
    );
  });

  it("throws when the op reverts on-chain (success: false)", async () => {
    vi.mocked(trpcRequest).mockResolvedValue({
      status: 200,
      data: { hash: "0xtx", success: false, reason: "AA50 reverted" },
      text: "",
    });
    await expect(signSimulateSubmit(params())).rejects.toThrow(
      /reverted on-chain: AA50 reverted \(tx 0xtx\)/,
    );
  });

  it("treats an absent success flag as failure (never a false mint)", async () => {
    // A response carrying a hash but no `success` must not be reported as minted.
    vi.mocked(trpcRequest).mockResolvedValue({
      status: 200,
      data: { hash: "0xtx" },
      text: "",
    });
    await expect(signSimulateSubmit(params())).rejects.toThrow(
      /reverted on-chain: unknown/,
    );
  });
});
