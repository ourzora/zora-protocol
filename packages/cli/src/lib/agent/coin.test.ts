import { describe, it, expect, vi, beforeEach } from "vitest";

vi.mock("./zora-client.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("./zora-client.js")>();
  return { ...actual, trpcRequest: vi.fn() };
});
vi.mock("./submit.js", () => ({ signSimulateSubmit: vi.fn() }));

import { createCreatorCoin } from "./coin.js";
import { trpcRequest } from "./zora-client.js";
import { signSimulateSubmit } from "./submit.js";

const params = (over = {}) =>
  ({
    token: "tok",
    account: {},
    client: {},
    dryRun: false,
    ...over,
  }) as Parameters<typeof createCreatorCoin>[0];

beforeEach(() => {
  vi.clearAllMocks();
  vi.mocked(signSimulateSubmit).mockResolvedValue({
    sponsored: true,
    simulation: "ExecutionResult",
    submitted: { hash: "0xco", success: true },
  });
});

describe("createCreatorCoin", () => {
  it("builds the deploy UserOp and finalizes it", async () => {
    vi.mocked(trpcRequest).mockResolvedValue({
      status: 200,
      data: { sender: "0xsmart", nonce: "1" },
      text: "",
    });
    const result = await createCreatorCoin(params());
    expect(result.submitted?.hash).toBe("0xco");
    expect(signSimulateSubmit).toHaveBeenCalledWith(
      expect.objectContaining({
        raw: { sender: "0xsmart", nonce: "1" },
        dryRun: false,
      }),
    );
  });

  it("throws when the backend returns no UserOp", async () => {
    vi.mocked(trpcRequest).mockResolvedValue({
      status: 500,
      data: undefined,
      error: "server boom",
      text: "",
    });
    await expect(createCreatorCoin(params())).rejects.toThrow(
      /createDeployCreatorCoinUserOperation failed: server boom/,
    );
    expect(signSimulateSubmit).not.toHaveBeenCalled();
  });

  it("passes dryRun through to the finalize step", async () => {
    vi.mocked(trpcRequest).mockResolvedValue({
      status: 200,
      data: { sender: "0xsmart" },
      text: "",
    });
    await createCreatorCoin(params({ dryRun: true }));
    expect(signSimulateSubmit).toHaveBeenCalledWith(
      expect.objectContaining({ dryRun: true }),
    );
  });
});
