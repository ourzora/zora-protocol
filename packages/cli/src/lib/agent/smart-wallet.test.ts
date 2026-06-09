import { describe, it, expect, vi, beforeEach } from "vitest";
import type { ChainClient } from "./zora-client.js";

vi.mock("./zora-client.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("./zora-client.js")>();
  return { ...actual, trpcRequest: vi.fn(), graphqlRequest: vi.fn() };
});

import { provisionSmartWallet } from "./smart-wallet.js";
import { trpcRequest, graphqlRequest } from "./zora-client.js";

const EMBEDDED = "0xeee0000000000000000000000000000000000001" as const;
const EXTERNAL = "0xe0b59c6f976a33aace3ee77f585a7d542dd115f3" as const;
const TWO_OWNER = "0xaaaa000000000000000000000000000000000001" as const;
const ONE_OWNER = "0xbbbb000000000000000000000000000000000002" as const;
const noSleep = async () => {};

// Fake client: getAddress() returns a distinct address per owner-set; getCode()
// reports the two-owner wallet as deployed only after `deployedAfter` calls.
function makeClient(deployedAfter: number): ChainClient {
  let getCodeCalls = 0;
  return {
    readContract: async (args) => {
      const owners = (args?.args?.[0] as unknown[]) ?? [];
      return owners.length === 2 ? TWO_OWNER : ONE_OWNER;
    },
    getCode: async ({ address }) => {
      getCodeCalls++;
      return getCodeCalls > deployedAfter &&
        address.toLowerCase() === TWO_OWNER.toLowerCase()
        ? "0xabcd"
        : "0x";
    },
    call: async () => undefined,
  };
}

beforeEach(() => {
  vi.clearAllMocks();
  vi.mocked(trpcRequest).mockResolvedValue({ status: 200, data: {}, text: "" });
  vi.mocked(graphqlRequest).mockResolvedValue({
    status: 200,
    data: { linkSmartWallet: { walletAddress: TWO_OWNER } },
    text: "",
  });
});

describe("provisionSmartWallet", () => {
  it("polls for the asynchronously-confirmed deploy and resolves the two-owner wallet", async () => {
    const wallet = await provisionSmartWallet({
      token: "t",
      client: makeClient(2), // not deployed on the first round; appears on the next
      embedded: EMBEDDED,
      external: EXTERNAL,
      sleep: noSleep,
    });
    expect(wallet.address.toLowerCase()).toBe(TWO_OWNER);
    expect(wallet.owners).toEqual([EMBEDDED, EXTERNAL]);
  });

  it("throws after exhausting attempts if the deploy never confirms", async () => {
    await expect(
      provisionSmartWallet({
        token: "t",
        client: makeClient(999),
        embedded: EMBEDDED,
        external: EXTERNAL,
        resolveAttempts: 2,
        sleep: noSleep,
      }),
    ).rejects.toThrow(/after polling/i);
  });

  it("surfaces the deploy failure cause when nothing confirms on-chain", async () => {
    // A real failure (expired token, 429, network) must not be masked by the
    // generic "not found" — the tRPC error is appended to the thrown message.
    vi.mocked(trpcRequest).mockResolvedValue({
      status: 429,
      data: undefined,
      error: "rate limited",
      text: "",
    });
    await expect(
      provisionSmartWallet({
        token: "t",
        client: makeClient(999),
        embedded: EMBEDDED,
        external: EXTERNAL,
        resolveAttempts: 2,
        sleep: noSleep,
      }),
    ).rejects.toThrow(/HTTP 429: rate limited/);
  });

  it("rejects an embedded-only deploy — the external EOA can't sign UserOps", async () => {
    // Only the single-owner candidate is on-chain, so the external EOA isn't an owner.
    const embeddedOnly: ChainClient = {
      readContract: async (args) =>
        ((args?.args?.[0] as unknown[]) ?? []).length === 2
          ? TWO_OWNER
          : ONE_OWNER,
      getCode: async ({ address }) =>
        address.toLowerCase() === ONE_OWNER.toLowerCase() ? "0xabcd" : "0x",
      call: async () => undefined,
    };
    await expect(
      provisionSmartWallet({
        token: "t",
        client: embeddedOnly,
        embedded: EMBEDDED,
        external: EXTERNAL,
        sleep: noSleep,
      }),
    ).rejects.toThrow(/cannot sign UserOps headless/i);
    expect(graphqlRequest).not.toHaveBeenCalled();
  });

  it("retries the link through a deploy/index race", async () => {
    vi.mocked(graphqlRequest)
      .mockResolvedValueOnce({
        status: 200,
        data: undefined,
        errors: [{ message: "wallet not indexed yet" }],
        text: "",
      })
      .mockResolvedValueOnce({
        status: 200,
        data: { linkSmartWallet: { walletAddress: TWO_OWNER } },
        text: "",
      })
      .mockResolvedValueOnce({
        status: 200,
        data: { updateSmartWalletCreationOwners: {} },
        text: "",
      });
    const wallet = await provisionSmartWallet({
      token: "t",
      client: makeClient(0),
      embedded: EMBEDDED,
      external: EXTERNAL,
      sleep: noSleep,
    });
    expect(wallet.address.toLowerCase()).toBe(TWO_OWNER);
    expect(graphqlRequest).toHaveBeenCalledTimes(3); // 2 link attempts + owner-sync
  });

  it("throws when the link exhausts its attempts", async () => {
    vi.mocked(graphqlRequest).mockResolvedValue({
      status: 200,
      data: undefined,
      errors: [{ message: "boom" }],
      text: "",
    });
    await expect(
      provisionSmartWallet({
        token: "t",
        client: makeClient(0),
        embedded: EMBEDDED,
        external: EXTERNAL,
        linkAttempts: 2,
        sleep: noSleep,
      }),
    ).rejects.toThrow(/linkSmartWallet failed: boom/);
  });

  it("throws when owner-sync returns an error", async () => {
    vi.mocked(graphqlRequest)
      .mockResolvedValueOnce({
        status: 200,
        data: { linkSmartWallet: { walletAddress: TWO_OWNER } },
        text: "",
      })
      .mockResolvedValueOnce({
        status: 200,
        data: undefined,
        errors: [{ message: "owner sync failed" }],
        text: "",
      });
    await expect(
      provisionSmartWallet({
        token: "t",
        client: makeClient(0),
        embedded: EMBEDDED,
        external: EXTERNAL,
        sleep: noSleep,
      }),
    ).rejects.toThrow(
      /updateSmartWalletCreationOwners failed: owner sync failed/,
    );
  });
});
