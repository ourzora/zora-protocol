import { describe, it, expect, vi, beforeEach } from "vitest";

vi.mock("./zora-client.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("./zora-client.js")>();
  return { ...actual, ipfsUpload: vi.fn(), trpcRequest: vi.fn() };
});
vi.mock("./submit.js", () => ({ signSimulateSubmit: vi.fn() }));
// Stub the card renderer — Satori/resvg are heavy and exercised separately; here
// we only care that createFirstPost wires the card PNG through to IPFS.
vi.mock("./render-card.js", () => ({
  renderFirstPostCard: vi.fn(async () => Buffer.from("PNG")),
}));

import { createFirstPost, deriveTicker } from "./post.js";
import { ipfsUpload, trpcRequest } from "./zora-client.js";
import { signSimulateSubmit } from "./submit.js";
import { renderFirstPostCard } from "./render-card.js";

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
    caption: "gm",
    image: { bytes: new Uint8Array([1, 2, 3]), mimeType: "image/png" },
    handle: "zora.co/alice",
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
    expect(result.caption).toBe("gm");
    expect(result.ticker).toBe("GM");
    expect(renderFirstPostCard).toHaveBeenCalledWith(
      expect.objectContaining({ caption: "gm", handle: "zora.co/alice" }),
    );
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

  it("leaves coinAddress undefined when no log name matches the coin name", async () => {
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

  it("resolves the coin address from the tx receipt when inline logs are empty", async () => {
    // The common CI case: submitUserOperation returns no inline logs, so the
    // address must come from the mined transaction's receipt.
    vi.mocked(signSimulateSubmit).mockResolvedValue({
      sponsored: true,
      simulation: "ExecutionResult",
      submitted: { hash: "0xposttx", success: true, logs: [] },
    });
    const readContract = vi.fn(async () => "gm");
    const getTransactionReceipt = vi.fn(async () => ({
      logs: [{ address: COIN }],
    }));
    const client = { readContract, getTransactionReceipt };
    const result = await createFirstPost(
      params({ client, sleep: async () => {} }),
    );
    expect(getTransactionReceipt).toHaveBeenCalledWith({ hash: "0xposttx" });
    expect(result.coinAddress?.toLowerCase()).toBe(COIN);
  });

  it("prefers inline logs and never fetches the receipt when they match", async () => {
    vi.mocked(signSimulateSubmit).mockResolvedValue({
      sponsored: true,
      simulation: "ExecutionResult",
      submitted: { hash: "0xposttx", success: true, logs: [{ address: COIN }] },
    });
    const getTransactionReceipt = vi.fn();
    const client = {
      readContract: vi.fn(async () => "gm"),
      getTransactionReceipt,
    };
    const result = await createFirstPost(params({ client }));
    expect(result.coinAddress?.toLowerCase()).toBe(COIN);
    expect(getTransactionReceipt).not.toHaveBeenCalled();
  });

  it("polls then gives up gracefully when the receipt fetch keeps failing", async () => {
    vi.mocked(signSimulateSubmit).mockResolvedValue({
      sponsored: true,
      simulation: "ExecutionResult",
      submitted: { hash: "0xposttx", success: true, logs: [] },
    });
    const getTransactionReceipt = vi.fn(async () => {
      throw new Error("receipt not found");
    });
    const client = { readContract: vi.fn(), getTransactionReceipt };
    const result = await createFirstPost(
      params({ client, sleep: async () => {}, receiptAttempts: 3 }),
    );
    expect(getTransactionReceipt).toHaveBeenCalledTimes(3);
    expect(result.coinAddress).toBeUndefined();
  });

  it("fetches a successful receipt only once even when the coin isn't in its logs", async () => {
    // A fetched receipt is final, so an unmatched coin must not trigger re-polls
    // — that would just re-read identical logs and waste the retry budget.
    vi.mocked(signSimulateSubmit).mockResolvedValue({
      sponsored: true,
      simulation: "ExecutionResult",
      submitted: { hash: "0xposttx", success: true, logs: [] },
    });
    const getTransactionReceipt = vi.fn(async () => ({
      logs: [{ address: COIN }],
    }));
    const readContract = vi.fn(async () => "a different coin");
    const client = { readContract, getTransactionReceipt };
    const result = await createFirstPost(
      params({ client, sleep: async () => {}, receiptAttempts: 5 }),
    );
    expect(getTransactionReceipt).toHaveBeenCalledTimes(1);
    expect(result.coinAddress).toBeUndefined();
  });

  it("defaults the coin name + description to the caption", async () => {
    await createFirstPost(params({ caption: "hello world" }));
    const meta = JSON.parse(vi.mocked(ipfsUpload).mock.calls[1][2].toString());
    expect(meta.name).toBe("hello world");
    expect(meta.description).toBe("hello world");
    expect(meta.symbol).toBe("HELLOWORLD");
  });

  it("uses --title / --description for metadata when provided", async () => {
    await createFirstPost(
      params({ title: "My Post", description: "a longer description" }),
    );
    const meta = JSON.parse(vi.mocked(ipfsUpload).mock.calls[1][2].toString());
    expect(meta.name).toBe("My Post");
    expect(meta.description).toBe("a longer description");
    // Ticker derives from the title, not the caption, when a title is set.
    expect(meta.symbol).toBe("MYPOST");
  });

  it("uses a provided ticker verbatim instead of deriving one", async () => {
    await createFirstPost(params({ title: "My Post", ticker: "wagmi" }));
    const meta = JSON.parse(vi.mocked(ipfsUpload).mock.calls[1][2].toString());
    // The forced ticker wins over the title-derived "MYPOST".
    expect(meta.symbol).toBe("wagmi");
  });

  it("rejects an invalid forced ticker before uploading anything", async () => {
    await expect(
      createFirstPost(params({ ticker: "this-is-way-too-long-and-invalid" })),
    ).rejects.toThrow(/Ticker/);
    expect(ipfsUpload).not.toHaveBeenCalled();
    expect(signSimulateSubmit).not.toHaveBeenCalled();
  });
});

describe("deriveTicker", () => {
  it("uppercases alphanumerics and caps at 10 characters", () => {
    expect(deriveTicker("gm")).toBe("GM");
    expect(deriveTicker("hello, world!")).toBe("HELLOWORLD");
    expect(deriveTicker("supercalifragilistic")).toBe("SUPERCALIF");
  });

  it("falls back to POST when too little usable text remains", () => {
    expect(deriveTicker("🦭✨")).toBe("POST");
    expect(deriveTicker("   ")).toBe("POST");
    // A single alphanumeric is below the 2-char minimum, so it falls back too.
    expect(deriveTicker("x")).toBe("POST");
  });
});
