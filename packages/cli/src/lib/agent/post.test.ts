import { describe, it, expect, vi, beforeEach } from "vitest";

vi.mock("./zora-client.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("./zora-client.js")>();
  return { ...actual, ipfsUpload: vi.fn(), trpcRequest: vi.fn() };
});
vi.mock("./submit.js", () => ({ signSimulateSubmit: vi.fn() }));

import { createFirstPost } from "./post.js";
import { ipfsUpload, trpcRequest } from "./zora-client.js";
import { signSimulateSubmit } from "./submit.js";

const CARD = { greeting: "gm", ticker: "GM", pngBase64: "AAAA" };
const COIN = "0x1f6835c4996fad83c8af2afa00056adf9234fe72";
const SMART = "0xSmart00000000000000000000000000000000aaaa";
const OWNERS = [
  "0xEmbedded0000000000000000000000000000bbbb",
  "0xExternal0000000000000000000000000000cccc",
];

const params = (over = {}) =>
  ({
    token: "tok",
    account: {},
    client: {},
    smartWallet: SMART,
    owners: OWNERS,
    dryRun: false,
    card: CARD,
    ...over,
  }) as Parameters<typeof createFirstPost>[0];

beforeEach(() => {
  vi.clearAllMocks();
  vi.mocked(ipfsUpload).mockImplementation(async (_token, filename) =>
    filename === "metadata.json" ? "ipfs://meta" : "ipfs://img",
  );
  vi.mocked(trpcRequest).mockResolvedValue({
    status: 200,
    data: { sender: SMART },
    text: "",
  });
  vi.mocked(signSimulateSubmit).mockResolvedValue({
    sponsored: true,
    simulation: "ExecutionResult",
    submitted: { hash: "0xpost", success: true },
  });
});

describe("createFirstPost", () => {
  it("uploads the card image then metadata, and returns the URIs + result", async () => {
    const result = await createFirstPost(params());

    expect(result.imageUri).toBe("ipfs://img");
    expect(result.contractUri).toBe("ipfs://meta");
    expect(result.greeting).toBe("gm");
    expect(result.ticker).toBe("GM");
    expect(result.submitted?.hash).toBe("0xpost");
    expect(ipfsUpload).toHaveBeenNthCalledWith(
      1,
      "tok",
      "first-post.png",
      expect.anything(),
      "image/png",
    );
    expect(ipfsUpload).toHaveBeenNthCalledWith(
      2,
      "tok",
      "metadata.json",
      expect.anything(),
      "application/json",
    );
  });

  it("sends adminAddressess (the BFF's misspelled key) with owners + smart wallet", async () => {
    await createFirstPost(params());
    const call = vi.mocked(trpcRequest).mock.calls[0];
    expect(call[1]).toBe("create.createCreateERC20UserOperationV2");
    // The BFF's zod schema keys on the misspelled `adminAddressess`; the correctly
    // spelled key is rejected as a missing required array. See the note in post.ts.
    expect(call[2].json).toMatchObject({
      adminAddressess: [...OWNERS, SMART],
      contractURI: "ipfs://meta",
      ticker: "GM",
    });
    expect(call[2].json).not.toHaveProperty("adminAddresses");
  });

  it("throws when the backend returns no UserOp", async () => {
    vi.mocked(trpcRequest).mockResolvedValue({
      status: 500,
      data: undefined,
      error: "server boom",
      text: "",
    });
    await expect(createFirstPost(params())).rejects.toThrow(
      /createCreateERC20UserOperationV2 failed: server boom/,
    );
    expect(signSimulateSubmit).not.toHaveBeenCalled();
  });

  it("passes dryRun through to the finalize step", async () => {
    await createFirstPost(params({ dryRun: true }));
    expect(signSimulateSubmit).toHaveBeenCalledWith(
      expect.objectContaining({ dryRun: true }),
    );
  });

  it("resolves the post coin address from the submit logs", async () => {
    vi.mocked(signSimulateSubmit).mockResolvedValue({
      sponsored: true,
      simulation: "ExecutionResult",
      submitted: { hash: "0xpost", success: true, logs: [{ address: COIN }] },
    });
    const client = { readContract: vi.fn(async () => "gm") };
    const result = await createFirstPost(params({ client }));
    expect(result.coinAddress?.toLowerCase()).toBe(COIN);
  });

  it("leaves coinAddress undefined when no log name matches the greeting", async () => {
    vi.mocked(signSimulateSubmit).mockResolvedValue({
      sponsored: true,
      simulation: "ExecutionResult",
      submitted: { hash: "0xpost", success: true, logs: [{ address: COIN }] },
    });
    const client = { readContract: vi.fn(async () => "a different coin") };
    const result = await createFirstPost(params({ client }));
    expect(result.coinAddress).toBeUndefined();
  });

  it("ignores malformed logs without throwing or reading", async () => {
    vi.mocked(signSimulateSubmit).mockResolvedValue({
      sponsored: true,
      simulation: "ExecutionResult",
      submitted: {
        hash: "0xpost",
        success: true,
        logs: [{}, { address: null }, "junk"],
      },
    });
    const client = { readContract: vi.fn() };
    const result = await createFirstPost(params({ client }));
    expect(result.coinAddress).toBeUndefined();
    expect(client.readContract).not.toHaveBeenCalled();
  });
});
