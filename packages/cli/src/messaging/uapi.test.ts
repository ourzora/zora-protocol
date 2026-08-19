import { afterEach, describe, expect, it, vi } from "vitest";
import type { Address } from "viem";
import {
  checkNewDmConversationAllowed,
  graphqlRequest,
  registerXmtpInstallation,
  resolveProfiles,
  resolveHandleToAddress,
} from "./uapi.js";

const PEER = "0x1111111111111111111111111111111111111111" as Address;

const mockFetch = (
  impl: (url: string, init: RequestInit) => unknown,
): ReturnType<typeof vi.fn> => {
  const fn = vi.fn(async (url: string, init: RequestInit) => {
    const result = impl(url, init);
    return {
      ok: true,
      status: 200,
      json: async () => result,
      ...(result instanceof Response ? {} : {}),
    } as unknown as Response;
  });
  vi.stubGlobal("fetch", fn);
  return fn;
};

afterEach(() => {
  vi.unstubAllGlobals();
});

describe("graphqlRequest", () => {
  it("sends a bearer token and returns data", async () => {
    const fn = mockFetch(() => ({ data: { ok: true } }));
    const data = await graphqlRequest<{ ok: boolean }>("query", {}, "jwt");
    expect(data.ok).toBe(true);
    const init = fn.mock.calls[0][1] as RequestInit;
    expect((init.headers as Record<string, string>).authorization).toBe(
      "Bearer jwt",
    );
  });

  it("throws on GraphQL errors", async () => {
    mockFetch(() => ({ errors: [{ message: "boom" }] }));
    await expect(graphqlRequest("q", {})).rejects.toThrow(/boom/);
  });

  it("throws on non-OK HTTP", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => ({ ok: false, status: 503 }) as unknown as Response),
    );
    await expect(graphqlRequest("q", {})).rejects.toThrow(/HTTP 503/);
  });
});

describe("resolveProfiles", () => {
  it("resolves an address to its handle, display name, and avatar", async () => {
    const fn = mockFetch(() => ({
      profile: {
        __typename: "GraphQLAccountProfile",
        handle: "alice",
        username: "alice",
        displayName: "Alice ⚡️",
        avatar: { previewImage: { small: "https://img/small.png" } },
      },
    }));
    const map = await resolveProfiles([PEER]);
    expect(map.get(PEER)).toEqual({
      address: PEER,
      handle: "alice",
      displayName: "Alice ⚡️",
      avatarUrl: "https://img/small.png",
      platformBlocked: false,
    });
    // Hits the public profile endpoint with the address as identifier.
    expect(String(fn.mock.calls[0][0])).toContain(
      `/profile?identifier=${PEER}`,
    );
  });

  it("falls back to username when handle is absent", async () => {
    mockFetch(() => ({ profile: { username: "bob" } }));
    const map = await resolveProfiles([PEER]);
    expect(map.get(PEER)?.handle).toBe("bob");
  });

  it("serves a cached profile without re-fetching", async () => {
    const fn = mockFetch(() => ({ profile: { handle: "alice" } }));
    await resolveProfiles([PEER]); // miss → fetch + cache
    const map = await resolveProfiles([PEER]); // hit → no fetch
    expect(fn).toHaveBeenCalledTimes(1);
    expect(map.get(PEER)?.handle).toBe("alice");
  });

  it("reports lookup progress over uncached addresses", async () => {
    mockFetch(() => ({ profile: { handle: "x" } }));
    const calls: Array<[number, number]> = [];
    const addresses = Array.from(
      { length: 3 },
      (_, i) => `0x${String(i).padStart(40, "0")}` as Address,
    );
    await resolveProfiles(addresses, undefined, (done, total) =>
      calls.push([done, total]),
    );
    expect(calls[0]).toEqual([0, 3]);
    expect(calls.at(-1)).toEqual([3, 3]);
  });

  it("bounds lookup concurrency for a large batch of new senders", async () => {
    let inFlight = 0;
    let peak = 0;
    vi.stubGlobal(
      "fetch",
      vi.fn(async (url: string) => {
        inFlight += 1;
        peak = Math.max(peak, inFlight);
        await new Promise((r) => setTimeout(r, 5));
        inFlight -= 1;
        return {
          ok: true,
          status: 200,
          json: async () => ({ profile: { handle: "x" } }),
        } as unknown as Response;
      }),
    );
    const addresses = Array.from(
      { length: 20 },
      (_, i) => `0x${String(i).padStart(40, "0")}` as Address,
    );
    const map = await resolveProfiles(addresses);
    expect(map.size).toBe(20);
    expect(peak).toBeLessThanOrEqual(8);
  });

  it("is best-effort: a failed lookup yields a null-field entry, not a throw", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => ({ ok: false, status: 500 }) as unknown as Response),
    );
    const map = await resolveProfiles([PEER]);
    expect(map.get(PEER)).toEqual({
      address: PEER,
      handle: null,
      displayName: null,
      avatarUrl: null,
      platformBlocked: false,
    });
  });
});

describe("resolveHandleToAddress", () => {
  it("resolves a handle to its smart-wallet address (checksummed)", async () => {
    mockFetch(() => ({
      profile: {
        handle: "wbnns",
        linkedWallets: {
          edges: [
            {
              node: {
                walletType: "EXTERNAL",
                walletAddress: "0x60ec4fd8069513f738f3a0f41b9e00c294e74bf3",
              },
            },
            {
              node: {
                walletType: "SMART_WALLET",
                walletAddress: "0xd91d9de054e294d9bebb7149955457300a9305cc",
              },
            },
          ],
        },
      },
    }));
    expect(await resolveHandleToAddress("@wbnns")).toEqual({
      ok: true,
      address: "0xD91d9De054E294d9BEBB7149955457300A9305cC",
    });
  });

  it("reports no-inbox when the account has no smart wallet", async () => {
    mockFetch(() => ({
      profile: { handle: "x", linkedWallets: { edges: [] } },
    }));
    expect(await resolveHandleToAddress("x")).toEqual({
      ok: false,
      reason: "no-inbox",
    });
  });

  it("reports not-found when there is no account", async () => {
    mockFetch(() => ({ profile: null }));
    expect(await resolveHandleToAddress("ghost")).toEqual({
      ok: false,
      reason: "not-found",
    });
  });

  it("reports error on a transient API failure", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => ({ ok: false, status: 503 }) as unknown as Response),
    );
    expect(await resolveHandleToAddress("x")).toEqual({
      ok: false,
      reason: "error",
    });
  });
});

describe("checkNewDmConversationAllowed", () => {
  it("returns the gate result", async () => {
    mockFetch(() => ({
      data: {
        checkNewDmConversationAllowed: {
          allowed: false,
          retryAfterSeconds: 12,
        },
      },
    }));
    const result = await checkNewDmConversationAllowed(PEER, "jwt");
    expect(result).toEqual({ allowed: false, retryAfterSeconds: 12 });
  });
});

describe("registerXmtpInstallation", () => {
  it("registers with the CLI device platform and bearer auth", async () => {
    const fn = mockFetch(() => ({
      data: { registerXmtpInstallation: { id: "acct1" } },
    }));
    await registerXmtpInstallation("install-123", "jwt");

    const init = fn.mock.calls[0][1] as RequestInit;
    expect((init.headers as Record<string, string>).authorization).toBe(
      "Bearer jwt",
    );
    const body = JSON.parse(init.body as string);
    expect(body.variables).toEqual({
      installationId: "install-123",
      devicePlatform: "CLI",
    });
  });
});
